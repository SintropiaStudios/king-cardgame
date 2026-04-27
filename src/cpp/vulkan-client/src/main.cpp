#include "Application.h"
#include "Logger.h"
#include <iostream>

int main(int argc, char* argv[]) {
    try {
        Application app(argc, argv);
        app.run();
    } catch (const std::exception& e) {
        Logger::log(LogLevel::ERROR, "Fatal Application Error: ", e.what());
        return 1;
    }
    return 0;
}
