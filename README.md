# King: An Open Multiplayer Card Game Ecosystem

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Protocol](https://img.shields.io/badge/Protocol-ZMQ-green.svg)](protocol/)

King is a highly strategic, trick-taking card game built on an open, language-agnostic communication protocol. This repository serves as the reference implementation for the **Public King** ecosystem, featuring an authoritative server and a diverse range of clients and AI agents.

## 🃏 The Game

The basic rules of the game can be found on [Wikipedia](https://en.wikipedia.org/wiki/King_(card_game)).

At its core, King is a game of shifting objectives. A match is divided into two phases:
1.  **Negative Rounds (Penalties):** Players aim to avoid taking tricks, hearts, or the specific "King of Hearts" to prevent losing points.
2.  **Positive Rounds (Lances):** Players bid and compete to secure points through strategic play.

### The Rules of Engagement (The "Aloja")
This implementation follows a refined ruleset focused on player agency, born from extensive gaming experience in student residences (the "Aloja"). Key departures from traditional King include:
*   **Dynamic Round Selection:** We've removed the rigid and traditional sequence of hands. Players have absolute freedom to choose which hand to play based on their starting cards.
*   **Strict Bidding:** Precise lance resolutions and subtle discard mechanics (especially for the King of Hearts) transform every match into a battle of structural planning.
*   **The King's Strategy:** In the "No King of Hearts" hand (or simply "King"), players are not forced to play the King of Hearts when the round starts with Hearts, unless it is their only discard option.

## 🏗️ Architecture & Protocol

Public King is designed to be a polyglot playground. The server and clients communicate via a formalized protocol based on **ZeroMQ (ZMQ)**, allowing anyone to build their own client or AI agent in any language.

### Repository Structure
*   `protocol/`: Formal specification of the ZMQ protocol.
*   `src/haskell/`: The authoritative game server (Haskell).
*   `src/python/`: Reference implementation of the logic, server, and basic bots.
*   `src/cpp/`: High-performance clients (Console and Vulkan/3D).
*   `src/csharp/`: Graphical clients in .NET and MonoGame.
*   `src/nodejs/`: Web client implementation.
*   `src/rust/`: Experimental client in Rust.

## 🚀 Getting Started

### Requirements
*   **Python:** 3.8+ (for core logic and reference scripts).
*   **ZeroMQ:** Required for communication across all implementations.
*   **Language-specific tools:** GHC/Cabal (Haskell), CMake (C++), Node/NPM, etc.

### Running the Python Reference
1.  Navigate to `src/python/common` and ensure dependencies are installed.
2.  Start the server: `python src/python/server/server.py`
3.  Connect a bot: `python src/python/bot/random_bot.py`

## 🎓 Origins: The "Aloja"

King is more than an exercise in protocol architecture; it carries a deep personal mark. This specific ruleset was forged in the "Aloja" (short for *Alojamento*), a student residence where a dedicated group of players turned the game into a culture of strategic rivalry. As a tribute to these roots, the AI opponents you face carry the names of the characters who defined that era.

## 🤝 Contributions

Contributions of all kinds are welcome! Whether it's a new client implementation, fixes for the Haskell server, or improvements to the protocol documentation.

*See [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon) for details.*

---

**Licensing Note:** Most assets and code are provided under the MIT license. Some graphical assets in client implementations are used with permission or as placeholders (see internal client READMEs for specific disclaimers).
