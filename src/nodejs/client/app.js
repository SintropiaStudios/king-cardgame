const zmq = require("zeromq");
const http = require("http");
const { Server } = require("socket.io");

/**
 * Backend Proxy Configuration
 */
const PORT = process.env.PORT || 3000;
const FRONTEND_URL = process.env.FRONTEND_URL || "http://localhost:4321";
const ZMQ_REQ_ADDR = process.env.ZMQ_REQ_ADDR || "tcp://127.0.0.1:5555";
const ZMQ_SUB_ADDR = process.env.ZMQ_SUB_ADDR || "tcp://127.0.0.1:5556";

const server = http.createServer();
const io = new Server(server, {
    cors: {
        origin: [FRONTEND_URL, "https://raffaine.github.io", "https://sintropiastudios.github.io"],
        methods: ["GET", "POST"],
        credentials: true
    }
});

/**
 * Handle asynchronous subscriptions from ZeroMQ
 */
async function runSubscriptionHandler() {
    const sock = new zmq.Subscriber();
    sock.connect(ZMQ_SUB_ADDR);
    sock.subscribe("");

    console.log(`[ZMQ SUB] Connected to ${ZMQ_SUB_ADDR}`);

    try {
        for await (const [topic] of sock) {
            const msg = topic.toString();
            const args = msg.split(" ");
            const tableId = args[0];
            const content = args.slice(1).join(" ");
            
            // Forward message to everyone in the table room
            io.to(tableId).emit("info", content);

            // Log critical events for debugging
            if (content.startsWith("START") || content.startsWith("STARTHAND") || content.startsWith("TURN") || content.startsWith("GAME")) {
                console.log(`[ZMQ BCAST] Table ${tableId}: ${content}`);
            }
        }
    } catch (err) {
        console.error(`[ZMQ SUB ERROR] ${err}`);
    }
}

/**
 * Socket.io Connection Handler
 */
io.on("connection", (socket) => {
    console.log(`[Proxy] Client ${socket.id} connected from frontend`);

    const zmqReq = new zmq.Request();
    zmqReq.connect(ZMQ_REQ_ADDR);

    socket.on("disconnect", async () => {
        if (socket.table && socket.user && socket.secret) {
            try {
                await zmqReq.send(`LEAVE ${socket.user} ${socket.secret}`);
            } catch (err) {
                console.error(`Error sending LEAVE on disconnect: ${err}`);
            }
        }
        console.log(`[Proxy] Client ${socket.id} disconnected`);
    });

    socket.on("action", async (data) => {
        console.log(`[Proxy] Received action from ${socket.id}: ${data}`);
        const args = data.split(" ");
        const command = args[0];

        if (command === "JOIN" && args.length > 3) {
            socket.user = args[1];
            socket.table = args[3];
            socket.pendingJoin = true;
            socket.join(socket.table);
        } else if (command === "LEAVE") {
            socket.pendingLeave = true;
        } else if (command === "LISTUSERS") {
            socket.join("user-list-channel");
        }

        try {
            await zmqReq.send(data);
            const [response] = await zmqReq.receive();
            const respStr = response.toString();

            if (socket.pendingJoin) {
                if (respStr.startsWith("ERROR")) {
                    socket.leave(socket.table);
                    delete socket.table;
                } else {
                    socket.secret = respStr;
                }
                delete socket.pendingJoin;
            } else if (socket.pendingLeave) {
                socket.leave(socket.table);
                delete socket.table;
                delete socket.pendingLeave;
            }

            socket.emit("response", respStr);
        } catch (err) {
            console.error(`[ZMQ REQ ERROR] ${err}`);
            socket.emit("response", "ERROR: Proxy failed to communicate with Game Server");
        }
    });
});

server.listen(PORT, () => {
    console.log(`🚀 King Proxy Gateway running on http://localhost:${PORT}`);
    console.log(`📡 Allowing CORS from ${FRONTEND_URL}`);
    runSubscriptionHandler().catch(console.error);
});
