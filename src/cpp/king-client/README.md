# King Game C++ Client Library (`king-client`)

A modern, thread-safe, non-blocking C++ client library for the King card game protocol.

This library encapsulates all ZeroMQ socket details, string message serialization/parsing, and JSON parsing. It uses an internal background worker thread to run asynchronous networking, but dispatches all events/callbacks safely on the user's main thread when `update()` is called, making it perfect for game loops (like the `king-flagship` client) and CLI bots/agents.

## 📦 Requirements
- **CMake** 3.24+
- **vcpkg** (or another C++ package manager providing `cppzmq` and `nlohmann-json`)

## 🛠️ Building the Library & Agent Example

To compile the `king_client` static library and the `king_agent` CLI tool, run:

```bash
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=/path/to/your/vcpkg/scripts/buildsystems/vcpkg.cmake
cmake --build .
```

This will produce:
- `libking_client.a` (the static library)
- `king_agent` (the executable CLI agent)

## 🤖 Running the Example Agent

First, make sure the Haskell King server is running. Then, run the agent:

```bash
./king_agent [server_ip] [agent_username] [agent_password]
```

Example:
```bash
./king_agent 127.0.0.1 Player1 okn_pass
```

The agent will automatically authorize, search for tables (creating one if none are available, or joining if there is a spot), and play the game automatically.

## 📖 Library Usage Example

```cpp
#include "king/client.h"
#include <iostream>

using namespace king;

int main() {
    KingClient client;
    if (!client.connect("127.0.0.1")) {
        std::cerr << "Failed to connect!" << std::endl;
        return 1;
    }

    // Register callbacks
    client.set_on_game_start([](const std::string& table, const std::vector<std::string>& players) {
        std::cout << "Game started with " << players.size() << " players!" << std::endl;
    });

    client.set_on_turn([&client](const std::string& table, const std::string& active_player) {
        std::cout << "Active turn: " << active_player << std::endl;
    });

    // Authorize
    client.authorize("MyUser", "MyPass", [](bool success, const std::string& channel_or_error) {
        if (success) {
            std::cout << "Authorized! Private channel: " << channel_or_error << std::endl;
        } else {
            std::cerr << "Auth failed: " << channel_or_error << std::endl;
        }
    });

    // Main Loop
    while (true) {
        // Run update() to poll events and execute callbacks on this thread
        client.update();
        std::this_thread::sleep_for(std::chrono::milliseconds(16)); // ~60fps
    }

    return 0;
}
```
