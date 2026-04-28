FROM node:20-bookworm-slim

WORKDIR /app

# Copy package files first to leverage Docker layer caching
COPY package*.json ./

# Install dependencies (zeromq has prebuilt binaries for standard linux/amd64)
RUN npm ci --only=production

# Copy the bridge source code
COPY app.js ./

# Expose the port the Express/Socket.io server binds to
EXPOSE 3000

# Run the bridge
CMD ["node", "app.js"]
