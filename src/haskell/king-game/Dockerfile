# ==========================================
# Stage 1: The Builder
# ==========================================
FROM haskell:9.4-slim AS builder

WORKDIR /opt/build

# Install the system-level C libraries required by ZeroMQ
RUN apt-get update && apt-get install -y \
    libzmq3-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy the cabal files and source code
COPY . .

# Update cabal and build the executable
# (We use cabal install to easily extract the binary to a known location)
RUN cabal update && \
    cabal install exe:ServerMain \
    --installdir=/opt/build/bin \
    --overwrite-policy=always

# ==========================================
# Stage 2: The Production Runtime
# ==========================================
FROM debian:bullseye-slim

WORKDIR /app

# Install ONLY the runtime ZeroMQ library
RUN apt-get update && apt-get install -y \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled binary from the builder stage
COPY --from=builder /opt/build/bin/ServerMain /usr/local/bin/king-server

# Expose the REQ/REP and PUB/SUB ports
EXPOSE 5555 5556

# Run the server
CMD ["king-server"]
