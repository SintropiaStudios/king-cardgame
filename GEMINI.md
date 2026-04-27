# Public King - Open Ecosystem & Architecture

## 1. Project Vision
"King" is an open-source, multiplayer card game ecosystem built around a language-agnostic communication protocol. Our vision is to foster a highly accessible, community-driven environment characterized by:
* **An Open Protocol:** A formalized, text-based ZeroMQ (ZMQ) standard that any client or server can implement.
* **Polyglot Diversity:** First-class support for clients, servers, and AI agents written in any language (currently featuring Haskell, C++, C#, Python, Rust, and Node.js).
* **Pristine Codebase:** Well-commented, approachable code with a highly organized repository structure designed to welcome new contributors.
* **Extensibility:** The ability for players to seamlessly integrate custom UIs or user-provided AI agents.

## 2. The Open Ecosystem Stack
The Public King repository serves as the reference implementation and playground for the open protocol:
* **Authoritative Server:** Haskell (managing game state, rules validation, and event broadcasting via ZMQ).
* **Reference Clients:** Implementations available in C++ (Console), C# (.NET/MonoGame), Python, Rust, and Node.js.
* **Automated Agents:** Context-aware bots capable of playing full matches, serving as templates for community-developed AI.

## 3. Planned Actions & Roadmap

To achieve our open-source vision and scale the open King ecosystem, we are actively tracking the following initiatives:

### A. Repository Reorganization & Open Governance
* **Structural Cleanup:** Reorganize the repository to clearly isolate public protocol definitions, the reference Haskell server, and the various open-source clients.
* **Licensing & Legal Scaffolding:** Apply clear open-source licensing (e.g., MIT or Apache 2.0) across the repository.
* **Governance Framework:** Establish a `CONTRIBUTING.md`, a `CODE_OF_CONDUCT.md`, and standardized issue templates (Bug Reports, Feature Requests) to safely manage external contributions and project direction.

### B. Client & Frontend Expansion
* **Vanilla JS/HTML Client:** Flesh out a lightweight, zero-dependency browser client
