#pragma once
#include <string>
#include <functional>
#include <thread>
#include <atomic>
#include <queue>
#include <mutex>

class HaskellBridge {
public:
    // Pass in the command line args to boot the RTS
    HaskellBridge();
    ~HaskellBridge();

    // The method to start your ZMQ background threads
    void connectToServer(const std::string& subUrl, const std::string& pushUrl, 
                         const std::string& player, const std::string& password);

    // FFI callback will call this
    void pushAction(const char* action);
    
    // Main loop will call this
    bool pollAction(std::string& outAction);
    
    // Call this when the user actually clicks a button to reply to the server
    void submitAction(const std::string& reply);

    // Checks if the Haskell runtime is still alive
    bool isAlive() const;

    // Fetch the cards in hand
    std::vector<std::string> getPlayerHand();    
    // Fetch the cards in table
    std::vector<std::string> getTableCards();
    // Fetch the available rules 
    std::vector<std::string> getAvailableRules();

private:
    std::thread workerThread;
    std::atomic<bool> bridgeActive{false};

    std::queue<std::string> actionQueue;
    std::mutex queueMutex;
};
