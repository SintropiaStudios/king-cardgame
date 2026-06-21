cmake_minimum_required(VERSION 3.24)
project(king_client CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Find Dependencies
find_package(cppzmq CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)

# Define library target
add_library(king_client STATIC
    src/client.cpp
    src/types.cpp
)

# Include directories
target_include_directories(king_client PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

target_include_directories(king_client PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Link dependencies
target_link_libraries(king_client PUBLIC
    cppzmq
    nlohmann_json::nlohmann_json
)

# Example executable: automated bot/agent
add_executable(king_agent
    examples/king_agent.cpp
)

target_link_libraries(king_agent PRIVATE
    king_client
)
