# King Game :: C++ SDL Vulkan Client

## Building
### 1. Create build folder
`mkdir build && cd build`

### 2. Reconfigure (CMake will now automatically find the system libvulkan.so!)
`cmake .. -DCMAKE_TOOLCHAIN_FILE=~/vcpkg/scripts/buildsystems/vcpkg.cmake`

### 3. Rebuild your game
`make`

### 4. Profit!
`./KingGame`

### Single Block
```
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=~/vcpkg/scripts/buildsystems/vcpkg.cmake
make
```
