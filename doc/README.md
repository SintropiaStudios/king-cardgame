# Implementation Guide

The Open King ecosystem is designed to be language-agnostic. This directory contains detailed information about each implementation provided in the `src/` folder.

## 🏗️ Architectural Overview

The project is split into three main components across various languages:
- **Server:** Authoritative logic for game rules, state management, and communication.
- **Client:** Reference implementations for connecting to a server and handling game flow.
- **Bots (Agents):** Automated players demonstrating how to implement decision-making logic.

## 📚 Language-Specific Documentation

- [**Haskell**](haskell.md): The primary authoritative server and FFI bridge.
- [**Python**](python.md): Core reference implementation, including a server, client, and bots.
- [**C++**](cpp.md): High-performance Vulkan-based 3D client and Haskell FFI integration.
- [**C#**](csharp.md): Modern graphical client built with MonoGame and NetMQ.
- [**Node.js**](nodejs.md): Web-based proxy and browser client using Socket.io.
- [**Rust**](rust.md): Experimental lightweight client.

## 🤝 Standards

All implementations MUST adhere to the [ZeroMQ Protocol Specification](../protocol/zmq-protocol.md).
