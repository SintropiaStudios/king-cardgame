#pragma once

#include "VulkanRenderer.h"
#include "Camera.h"
#include "SceneManager.h"

#include "HaskellBridge.h"
#include "GameState.h"
#include "Font.h"

#include "ProcessManager.h"

#include <memory>
#include <vector>

class Application {
public:
    Application(int argc, char* argv[]);
    void run();

private:
    std::unique_ptr<HaskellBridge> bridge;
    std::unique_ptr<VulkanRenderer> renderer;
    Camera camera;
    Font mainFont; // Application owns the font
    bool isRunning;

    void handleEvents();

    ProcessManager processManager;
    GameState    gameState;
    SceneManager sceneManager{&gameState};
};
