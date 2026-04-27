# Contributing to the King Ecosystem

Welcome! We are thrilled that you are interested in contributing to King. 

King is designed as a language-agnostic, open-protocol card game ecosystem. Because of this polyglot nature, our contribution philosophy might be a little different from what you are used to. 

Before submitting a Pull Request or opening an issue, please take a moment to read through this guide to understand our vision and how you can best make an impact.

## Our Philosophy: Expand, Don't Mutate

The primary goal of this repository is to serve as the **Reference Implementation** for the King Protocol. It contains the authoritative Haskell server, the official protocol documentation, and baseline reference clients (Python, Rust, C#, Node.js).

**We strongly encourage expanding the ecosystem rather than building into the core.** What does this mean for you?
1. **Use this repo as a reference:** Instead of adding a massive new UI or a highly complex AI agent directly into this repository, we encourage you to build it in your own standalone repository using your preferred tech stack.
2. **Build around the protocol:** Write a client in a language we haven't supported yet. Build a machine-learning bot. Create a web-based tournament tracker. The ZeroMQ (ZMQ) protocol is completely open for you to hook into.
3. **Graduation to Core:** If you build a client, server, or tool that gains significant community traction and proves its stability, the maintainers may reach out to officially incorporate it into the main repository or the official King organization.

## How You Can Contribute Directly

While we encourage external expansion, we absolutely welcome direct contributions to this repository in the following areas:

### 1. Protocol Documentation & Guides
The ecosystem is only as good as its documentation. Contributions that clarify the ZMQ API, add sequence diagrams, fix typos, or provide "Getting Started" tutorials for new languages are highly prized.

### 2. Hardening the Reference Server (Haskell)
The Haskell server is the authoritative rule-keeper for Version 1 of the Protocol. We welcome PRs that:
* Fix protocol compliance bugs.
* Improve edge-case handling and connection stability.
* Enhance test coverage for server logic.

### 3. Reference Client Bug Fixes
If you find a bug in one of the existing reference clients (Rust, Python, Node.js, C#) that prevents it from correctly parsing the protocol, please open an issue or submit a fix. *(Note: We generally do not accept feature bloat for reference clients; they should remain minimal and readable for educational purposes).*

## Submitting a Bug Report

When opening an issue to report a bug, please provide as much context as possible so we can reproduce it:
* **The Component:** Are you reporting an issue with the Haskell server, a specific reference client, or the protocol documentation?
* **Steps to Reproduce:** A clear, step-by-step guide to triggering the bug.
* **Expected vs. Actual Behavior:** What happened, and what did you expect to happen based on the protocol?
* **Logs & Traces:** Please include the raw ZMQ string payloads leading up to the error.

## Pull Request Process

If you are submitting a fix or documentation update to this repository, please follow these steps:

1. **Fork the repository** and create your branch from `main`.
2. **Keep it focused:** Ensure your PR does one specific thing. Do not bundle documentation updates with server logic fixes.
3. **Test your changes:** If modifying the Haskell server, ensure all compliance tests pass and that it can still successfully complete a match against the reference bots.
4. **Update documentation:** If you change any behavior related to the ZMQ payloads, you **must** update the corresponding protocol documentation in the same PR.
5. **Sign the CLA:** (If applicable in the future, you may be asked to sign a Contributor License Agreement).

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inspiring environment for all developers, regardless of their background or level of experience.

---

Thank you for helping us build the ultimate open-source card game ecosystem. We can't wait to see what you build!
