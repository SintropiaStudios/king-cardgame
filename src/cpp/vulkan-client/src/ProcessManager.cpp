#include "ProcessManager.h"
#include "Logger.h"
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <iostream>
#include <thread>
#include <chrono>
#include <random>
#include <algorithm>
#include <spawn.h>
#include <csignal>

// Required by posix_spawnp to pass the host environment variables to Haskell
extern char **environ; 

// Initialize the global pointer
static ProcessManager* globalInstance = nullptr;

/* static */ ProcessManager* ProcessManager::get() {
    return globalInstance;
}

// The global crash handler
void handleCrashSignal(int signal) {
    if (globalInstance) {
        std::cerr << "\n[CRASH HANDLER] Signal " << signal << " caught! Terminating Haskell bots..." << std::endl;
        globalInstance->terminateAll();
    }
    // Restore default OS behavior and re-raise so the process actually dies
    std::signal(signal, SIG_DFL);
    std::raise(signal);
}

ProcessManager::ProcessManager() {
    globalInstance = this;
    std::signal(SIGINT, handleCrashSignal);
    std::signal(SIGTERM, handleCrashSignal);
    std::signal(SIGSEGV, handleCrashSignal); // Catch those segmentation faults!
    std::signal(SIGABRT, handleCrashSignal);
}

ProcessManager::~ProcessManager() {
    terminateAll();
    globalInstance = nullptr;
}

bool ProcessManager::initialize(std::function<void()> connectPlayerCallback) {
    Logger::log(LogLevel::INFO, "[ProcessManager] Starting Match Orchestration...");

    // 1. Launch the Server
    if (!launchServer()) {
        return false;
    }

    // Give the Haskell server 500ms to open its TCP ports
    std::this_thread::sleep_for(std::chrono::milliseconds(800));

    // 2. CONNECT THE C++ CLIENT FIRST
    if (connectPlayerCallback) {
        Logger::log(LogLevel::INFO, "[ProcessManager] Executing player connection callback...");
        connectPlayerCallback();
    }

    // Give the server 100ms to process our join and create the table
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // 3. Launch the 3 Bots to fill the remaining seats
    return launchBots(3);
}

pid_t ProcessManager::spawnProcess(const std::string& executablePath, const std::vector<std::string>& args) {
    pid_t pid;

    // Tell the OS to look in the current working directory
    std::string fullPath = "./" + executablePath;

    // Build the C-string array just like before
    std::vector<char*> c_args;
    c_args.push_back(const_cast<char*>(executablePath.c_str())); 
    for (const auto& arg : args) {
        c_args.push_back(const_cast<char*>(arg.c_str()));
    }
    c_args.push_back(nullptr); 

    // posix_spawnp safely launches the process without duplicating Vulkan's memory!
    if (posix_spawnp(&pid, fullPath.c_str(), nullptr, nullptr, c_args.data(), environ) != 0) {
        Logger::log(LogLevel::ERROR, "[ProcessManager] posix_spawn failed for ", executablePath);
        return -1;
    }

    return pid;
}

bool ProcessManager::launchServer() {
    Logger::log(LogLevel::INFO, "[ProcessManager] Spawning Haskell Server...");
    
    // Using the exact name from your CMake script
    serverPid = spawnProcess("king-game-server-exe"); 
    
    if (serverPid > 0) {
        Logger::log(LogLevel::INFO, "[ProcessManager] Server spawned successfully. PID: ", serverPid);
        return true;
    }
    return false;
}

bool ProcessManager::launchBots(int count) {
    Logger::log(LogLevel::INFO, "[ProcessManager] Spawning ", count, " Haskell Bots...");
    bool success = true;

    // Our glorious roster of AI opponents
    std::vector<std::string> botNames = {
        "D2", "3_Horas", "Samurai", "Barata", "Regiane", "Ana_Maria",
        "Matheus", "Cartola", "Capitu", "Bentinho", "Lampião"
    };

    // Shuffle the names so every match has a unique cast of characters
    std::random_device rd;
    std::mt19937 generator(rd());
    std::shuffle(botNames.begin(), botNames.end(), generator);

    for (int i = 0; i < count; ++i) {
        // Grab a name from our shuffled list
        std::string name = (i < botNames.size()) ? botNames[i] : "Bot_" + std::to_string(i);
        std::string password = "a"; // The highly secure dummy password

        // Pass the name and password to the Haskell executable!
        pid_t botPid = spawnProcess("king-game-client-exe", {name, password});

        if (botPid > 0) {
            botPids.push_back(botPid);
            Logger::log(LogLevel::INFO, "[ProcessManager] Bot ", i+1, " spawned. PID: ", botPid);
            
            // Give each bot a tiny fraction of a second to bind before hitting the server simultaneously
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        } else {
            success = false;
        }
    }
    return success;
}

void ProcessManager::terminateAll() {
    // 1. Kill the bots
    for (pid_t pid : botPids) {
        if (pid > 0) {
            Logger::log(LogLevel::VERBOSE, "Terminating Bot PID: ", pid);
            kill(pid, SIGTERM);
            waitpid(pid, nullptr, WNOHANG); // Clean up the zombie entry
        }
    }
    botPids.clear();

    // 2. Kill the server
    if (serverPid > 0) {
        Logger::log(LogLevel::VERBOSE, "Terminating Server PID: ", serverPid);
        kill(serverPid, SIGTERM);
        waitpid(serverPid, nullptr, WNOHANG);
        serverPid = -1;
    }
}
