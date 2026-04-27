#pragma once
#include <string>
#include <vector>
#include <sys/types.h>
#include <functional>

class ProcessManager {
public:
    ProcessManager();
    ~ProcessManager(); // Crucial: Automatically kills children on exit

    bool initialize(std::function<void()> connectPlayerCallback);

    bool launchServer();
    bool launchBots(int count);
    void terminateAll();

    static ProcessManager* get();
    
private:
    pid_t serverPid = -1;
    std::vector<pid_t> botPids;

    // Helper to spawn a single executable
    pid_t spawnProcess(const std::string& executablePath, const std::vector<std::string>& args = {});
};
