# Rust Implementation

The Rust implementation provides a lightweight, experimental client.

## 🦀 Lightweight Client

Located in `src/rust/client/`, this implementation demonstrates a minimal ZeroMQ client using the `zmq` crate.

### Requirements
- **Rust Toolchain**
- **ZeroMQ** system library
- **pkg-config** (to locate ZeroMQ during build)

### Build and Run

```bash
cd src/rust/client
cargo run -- <username> <password>
```

## 📂 Structure
- `src/main.rs`: Single-file implementation of the client logic and ZeroMQ communication.
- `Cargo.toml`: Dependency configuration.
