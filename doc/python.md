# Python Implementation

The Python implementation provides the core reference for the King game logic and the original ZeroMQ protocol implementation.

## 📂 Structure

- `src/python/common/`: Shared game rules (`king.py`) and database utilities.
- `src/python/server/`: The reference server implementation and match-making logic.
- `src/python/client/`: Base client library and a console-based human client.
- `src/python/bot/`: Example AI agents (e.g., `random_bot.py`).

## 🛠️ Setup

Requires Python 3.8+ and the `pyzmq` and `pymongo` libraries.

```bash
pip install pyzmq pymongo
```

## 🚀 Usage

### Starting the Server
```bash
python src/python/server/server.py
```

### Joining with a Human Client
```bash
python src/python/client/human.py <username> <password>
```

### Running a Bot
```bash
python src/python/bot/random_bot.py <botname> <password>
```
