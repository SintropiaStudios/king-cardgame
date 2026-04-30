FROM node:20-bookworm-slim

WORKDIR /app

# Copy package files first to leverage Docker layer caching
COPY package*.json ./

# Install dependencies (zeromq has prebuilt binaries for standard linux/amd64)
RUN npm ci --only=production

# Copy the bridge source code
COPY app.js ./

# Set production defaults (Local dev will still fallback to localhost via app.js)
ENV ZMQ_REQ_ADDR=tcp://okn-server.sintropiastudios.com:5555
ENV ZMQ_SUB_ADDR=tcp://okn-server.sintropiastudios.com:5556
ENV FRONTEND_URL=https://sintropiastudios.github.io

# Expose the port the Express/Socket.io server binds to
EXPOSE 3000

# Run the bridge
CMD ["node", "app.js"]
