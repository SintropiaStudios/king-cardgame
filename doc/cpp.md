# C++ Implementation

The C++ implementation features a high-performance graphical client built with Vulkan.

## 📦 Vulkan Client

Located in `src/cpp/vulkan-client`, this client provides a 3D visualization of the game. It uses a unique architecture where it embeds the Haskell game engine via a Foreign Function Interface (FFI) to handle the complex state machine and networking.

### Requirements
- **Vulkan SDK**
- **GHC/Cabal** (for building the Haskell backend)
- **CMake 3.15+**
- **vcpkg** (for dependency management)

### Build Instructions

The CMake configuration is set up to automatically build the Haskell backend and link against the resulting shared library.

```bash
cd src/cpp/vulkan-client
mkdir build && cd build
cmake ..
make
```

## 📂 Structure
- `src/`: C++ source code.
- `shaders/`: GLSL shaders for the Vulkan renderer.
- `assets/`: Textures and fonts.
