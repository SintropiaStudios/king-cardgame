# ==========================================
# Stage 1: The Builder
# ==========================================
FROM haskell:9.4 AS builder

WORKDIR /opt/build

# Rewire the package manager to point to the permanent Debian Buster archives
# This completely bypasses the 404 Not Found errors.
RUN echo "deb http://archive.debian.org/debian buster main" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security buster/updates main" >> /etc/apt/sources.list

# Install the system-level C libraries required by ZeroMQ
# (We bypass the valid-until check because the archive dates are frozen)
RUN apt-get update -o Acquire::Check-Valid-Until=false && apt-get install -y \
    libzmq3-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Copy the cabal files and source code
COPY . .

# Update cabal and build the executable
RUN cabal update && \
    cabal install exe:king-game-server-exe \
    --installdir=/opt/build/bin \
    --overwrite-policy=always

# ==========================================
# Stage 2: The Production Runtime
# ==========================================
FROM debian:bookworm-slim

WORKDIR /app

# Install ONLY the runtime ZeroMQ library
RUN apt-get update && apt-get install -y \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled binary from the builder stage
COPY --from=builder /opt/build/bin/king-game-server-exe /usr/local/bin/king-server

# Expose the REQ/REP and PUB/SUB ports
EXPOSE 5555 5556

# Run the server
CMD ["king-server"]
