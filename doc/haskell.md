# Haskell Implementation

The Haskell implementation resides in `src/haskell/king-game` and serves as the primary authoritative server for the King ecosystem.

## 📦 Components

- **Server:** A robust, state-machine-driven game server located in `app/ServerMain.hs` and `src/ServerLogic.hs`.
- **Client:** A CLI-based client located in `app/ClientMain.hs`.
- **FFI Bridge:** A native C-compatible library (`src/ClientFFI.hs`) that allows the C++ Vulkan client to leverage the Haskell game logic.

## 🛠️ Build Instructions

Ensure you have [GHC](https://www.haskell.org/ghc/) and [Cabal](https://www.haskell.org/cabal/) installed.

```bash
cd src/haskell/king-game
cabal build
```

## 🚀 Running the Server

```bash
cabal run king-game-server-exe
```
The server will listen on ports `5555` (REQ/REP) and `5556` (PUB/SUB).
