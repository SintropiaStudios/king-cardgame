#include "Logger.h"

// Default to VERBOSE in Debug mode, but INFO in Release mode
#ifdef NDEBUG
LogLevel Logger::currentLevel = LogLevel::INFO;
#else
LogLevel Logger::currentLevel = LogLevel::VERBOSE;
#endif

void Logger::setLevel(LogLevel level) {
    currentLevel = level;
}
