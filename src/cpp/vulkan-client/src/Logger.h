#pragma once
#include <iostream>
#include <string>

enum class LogLevel {
    VERBOSE = 0,
    INFO,
    WARNING,
    ERROR,
    NONE // Set to this to mute everything
};

class Logger {
public:
    // Change the global log level at runtime
    static void setLevel(LogLevel level);

    // Modern C++17 variadic template to accept any number of arguments
    template<typename... Args>
    static void log(LogLevel level, Args&&... args) {
        if (level < currentLevel) return;

        // Route errors to standard error, everything else to standard out
        std::ostream& stream = (level == LogLevel::ERROR) ? std::cerr : std::cout;

        switch (level) {
            case LogLevel::VERBOSE: stream << "[VERBOSE] "; break;
            case LogLevel::INFO:    stream << "[INFO] "; break;
            case LogLevel::WARNING: stream << "[WARNING] "; break;
            case LogLevel::ERROR:   stream << "[ERROR] "; break;
            default: break;
        }

        // C++17 Fold Expression: Unpacks and prints all arguments sequentially
        (stream << ... << std::forward<Args>(args));
        
        stream << std::endl;
    }

private:
    static LogLevel currentLevel;
};
