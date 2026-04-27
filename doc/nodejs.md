# Node.js Implementation

The Node.js implementation features a web-based client and a proxy server that bridges ZeroMQ to WebSockets.

## 🌐 Web Client & Proxy

Located in `src/nodejs/client/`, this implementation allows playing the game in a web browser.

### Components
- **Proxy Server (`app.js`):** An Express and Socket.io server that communicates with the ZeroMQ backend.
- **Web UI (`index.html`, `public/`):** A front-end built with jQuery and CSS animations to render the game.

### Requirements
- **Node.js 18+**
- **ZeroMQ** system library

### Installation and Usage

```bash
cd src/nodejs/client
npm install
node app.js
```
The client will be available at `http://localhost:8086`.

## 📂 Structure
- `public/`: Client-side JavaScript (`king.js`) and CSS.
- `graphics/`: Placeholder and UI assets.
