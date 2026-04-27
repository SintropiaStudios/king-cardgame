cmake_minimum_required(VERSION 3.15)
project(KingClientRender VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ------------------------------------------------------------------
# Dependencies (vcpkg handles SDL and Vulkan)
# ------------------------------------------------------------------
find_package(SDL2 CONFIG REQUIRED)
find_package(Vulkan REQUIRED)

# Find Haskell build tools
find_program(CABAL_EXECUTABLE cabal REQUIRED)
find_program(GHC_EXECUTABLE ghc REQUIRED)

# ------------------------------------------------------------------
# Dynamically locate GHC's global include directory (for HsFFI.h)
# ------------------------------------------------------------------
execute_process(
    COMMAND ${GHC_EXECUTABLE} --print-libdir
    OUTPUT_VARIABLE GHC_LIBDIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Force CMake to recursively search every subfolder in the GHC lib directory
file(GLOB_RECURSE HSFFI_HEADERS "${GHC_LIBDIR}/*HsFFI.h")

if(NOT HSFFI_HEADERS)
    message(FATAL_ERROR "Could not find HsFFI.h anywhere inside ${GHC_LIBDIR}")
endif()

# Grab the first match and extract just the directory path
list(GET HSFFI_HEADERS 0 HSFFI_FILE)
get_filename_component(GHC_INCLUDE_DIR "${HSFFI_FILE}" DIRECTORY)

message(STATUS "SUCCESS! Found HsFFI.h in: ${GHC_INCLUDE_DIR}")

# ------------------------------------------------------------------
# Dynamically locate the Haskell RTS Library
# ------------------------------------------------------------------
# Hunt for the dynamically versioned libHSrts shared object
file(GLOB_RECURSE RTS_LIBS "${GHC_LIBDIR}/*libHSrts-*.so")

# Fallback just in case it doesn't have the version suffix
if(NOT RTS_LIBS)
    file(GLOB_RECURSE RTS_LIBS "${GHC_LIBDIR}/*libHSrts.so")
endif()

if(RTS_LIBS)
    # Grab the first match (usually the primary dynamically linked RTS)
    list(GET RTS_LIBS 0 GHC_RTS_LIBRARY)
    message(STATUS "[Haskell FFI] SUCCESS! Found Haskell RTS: ${GHC_RTS_LIBRARY}")
else()
    message(FATAL_ERROR "[Haskell FFI] Could not find libHSrts.so anywhere inside ${GHC_LIBDIR}")
endif()

# ------------------------------------------------------------------
# Setup the Automated Cabal Build Target
# ------------------------------------------------------------------
# Convert the relative path '..' into a concrete absolute path
get_filename_component(HASKELL_PROJECT_ROOT "${CMAKE_SOURCE_DIR}/../../haskell/king-game" ABSOLUTE)

set(SERVER_EXE "king-game-server-exe")
set(BOT_EXE "king-game-client-exe")

set(HASKELL_OUT_LIB_DIR "${CMAKE_BINARY_DIR}/haskell_artifacts/lib")
set(HASKELL_OUT_INC_DIR "${CMAKE_BINARY_DIR}/haskell_artifacts/include")

# 1. Write a CMake script to be executed at BUILD time
set(COPY_SCRIPT "${CMAKE_BINARY_DIR}/copy_artifacts.cmake")
file(WRITE ${COPY_SCRIPT} "
message(STATUS \"[Haskell FFI] Hunting for artifacts in: ${HASKELL_PROJECT_ROOT}/dist-newstyle\")

# Use CMake's native recursive globbing to find the files
file(GLOB_RECURSE SO_FILES \"${HASKELL_PROJECT_ROOT}/dist-newstyle/*libkingclient.so*\")
file(GLOB_RECURSE HEADER_FILES \"${HASKELL_PROJECT_ROOT}/dist-newstyle/*ClientFFI_stub.h\")

# Copy them to our clean directories
if(SO_FILES)
    list(GET SO_FILES 0 SOURCE_SO)
    message(STATUS \"[Haskell FFI] Found Library Artifact: \${SOURCE_SO}\")
    
    # 1. Copy the actual heavy binary once
    execute_process(COMMAND \${CMAKE_COMMAND} -E copy \"\${SOURCE_SO}\" \"${HASKELL_OUT_LIB_DIR}/libkingclient.so.0.0.1\")
    
    # 2. Create the exact relative symlinks the compiler and runtime expect!
    # (Using WORKING_DIRECTORY ensures the symlinks are relative and portable)
    execute_process(
        COMMAND \${CMAKE_COMMAND} -E create_symlink \"libkingclient.so.0.0.1\" \"libkingclient.so.0\"
        WORKING_DIRECTORY \"${HASKELL_OUT_LIB_DIR}\"
    )
    execute_process(
        COMMAND \${CMAKE_COMMAND} -E create_symlink \"libkingclient.so.0.0.1\" \"libkingclient.so\"
        WORKING_DIRECTORY \"${HASKELL_OUT_LIB_DIR}\"
    )
else()
    message(FATAL_ERROR \"[Haskell FFI] Could not find any libkingclient.so files!\")
endif()
if(HEADER_FILES)
    list(GET HEADER_FILES 0 FIRST_HEADER_FILE)
    message(STATUS \"[Haskell FFI] Found Header: \${FIRST_HEADER_FILE}\")
    file(COPY \${HEADER_FILES} DESTINATION \"${HASKELL_OUT_INC_DIR}\")
endif()
")

# 2. The Custom Target runs Cabal, then runs the CMake script we just wrote!
add_custom_target(haskell_backend ALL
    # Builds Haskel Binaries
    COMMAND ${CABAL_EXECUTABLE} build ${SERVER_EXE}
    COMMAND ${CABAL_EXECUTABLE} build ${BOT_EXE}
    # After building, copy the executables to the CMake binary dir so C++ can easily spawn them
    COMMAND cp `${CABAL_EXECUTABLE} list-bin -v0 ${SERVER_EXE}` ${CMAKE_BINARY_DIR}/${SERVER_EXE}
    COMMAND cp `${CABAL_EXECUTABLE} list-bin -v0 ${BOT_EXE}` ${CMAKE_BINARY_DIR}/${BOT_EXE}

    # Builds the C++ FFI
    COMMAND ${CABAL_EXECUTABLE} build kingclient
    # ${CMAKE_COMMAND} is the path to the cmake executable itself. 
    # -P tells it to process the script without configuring a project.
    COMMAND ${CMAKE_COMMAND} -P ${COPY_SCRIPT}
    WORKING_DIRECTORY ${HASKELL_PROJECT_ROOT}
    COMMENT "Building Haskell backend and extracting artifacts using native CMake..."
)

# ------------------------------------------------------------------
# Compile GLSL Shaders to SPIR-V
# ------------------------------------------------------------------
find_program(GLSLC glslc)
if(NOT GLSLC)
    message(FATAL_ERROR "glslc not found! Please run: sudo apt install glslc")
endif()

# Define where our shaders live and where the compiled binaries should go
set(SHADER_SRC_DIR "${CMAKE_SOURCE_DIR}/shaders")
set(SHADER_BIN_DIR "${CMAKE_BINARY_DIR}/shaders")
file(MAKE_DIRECTORY ${SHADER_BIN_DIR})

set(SHADERS 
    ${SHADER_SRC_DIR}/shader.vert 
    ${SHADER_SRC_DIR}/shader.frag
)

set(COMPILED_SHADERS "")

# Loop through each shader and create a custom command to compile it
foreach(SHADER ${SHADERS})
    get_filename_component(FILE_NAME ${SHADER} NAME)
    set(SPV_FILE "${SHADER_BIN_DIR}/${FILE_NAME}.spv")
    
    add_custom_command(
        OUTPUT ${SPV_FILE}
        COMMAND ${GLSLC} ${SHADER} -o ${SPV_FILE}
        DEPENDS ${SHADER}
        COMMENT "[Shaders] Compiling ${FILE_NAME} to SPIR-V..."
    )
    list(APPEND COMPILED_SHADERS ${SPV_FILE})
endforeach()

# Create a custom target that runs before our main executable builds
add_custom_target(compile_shaders ALL DEPENDS ${COMPILED_SHADERS})


# ------------------------------------------------------------------
# The C++ Executable Setup
# ------------------------------------------------------------------
add_executable(KingGame 
    src/main.cpp
    src/stb_image.cpp    
    src/stb_truetype.cpp
    src/Application.cpp
    src/ProcessManager.cpp
    src/VulkanRenderer.cpp 
    src/HaskellBridge.cpp
    src/Card.cpp
    src/Font.cpp
    src/Logger.cpp
    src/SceneManager.cpp
    src/BaseGameScene.cpp
    src/TitleScene.cpp
    src/InGameScene.cpp
    src/RuleSelectionScene.cpp
)

# Tell CMake it MUST build the Haskell backend before compiling C++
add_dependencies(KingGame haskell_backend)

# Tell CMake to build the shaders before trying to build the game
add_dependencies(KingGame compile_shaders)

# Include the dynamically found GHC headers AND our freshly copied FFI stub
target_include_directories(KingGame PRIVATE 
    ${GHC_INCLUDE_DIR}
    ${HASKELL_OUT_INC_DIR}
)

# Tell the linker where to find our freshly copied libkingclient.so
target_link_directories(KingGame PRIVATE ${HASKELL_OUT_LIB_DIR})

# Link everything together
target_link_libraries(KingGame PRIVATE
    SDL2::SDL2
    SDL2::SDL2main
    Vulkan::Vulkan
    kingclient
    ${GHC_RTS_LIBRARY} # Haskell Runtime
)
