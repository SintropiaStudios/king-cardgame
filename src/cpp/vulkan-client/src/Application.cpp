#include "Application.h"
#include <SDL2/SDL_vulkan.h>

#include "TitleScene.h"

#include "Logger.h"
#include <iostream>
#include <thread>

Application::Application(int argc, char* argv[]) : isRunning(false) {
    // 1. Boot the Haskell Engine
    bridge = std::make_unique<HaskellBridge>();
    
    // 1.1. Sending to Haskell
    gameState.submitAction = [this](const std::string& reply) {
        bridge->submitAction(reply);
    };

    // 1.2. Fetching from Haskell and feeding the Scene
    // gameState.pollCommand = [this](Scene* activeScene) {
    //     std::string cmd;
    //     // Drain the thread-safe queue from the bridge
    //     while (bridge->pollAction(cmd)) {
    //         Logger::log(LogLevel::INFO, "[Application] Dispatching command to Scene: ", cmd);
    //         activeScene->processCommand(cmd);
    //     }
    // };

    // 1.3 Wire the state fetchers
    gameState.getPlayerHand = [this]() {
        return bridge->getPlayerHand();
    };
    gameState.getTableCards = [this]() {
        return bridge->getTableCards();
    };
    gameState.getAvailableRules = [this]() {
        return bridge->getAvailableRules();
    };

    // 2. Boot the GPU Renderer
    renderer = std::make_unique<VulkanRenderer>("King Game", 1280, 720);
}

void Application::run() {    
    Logger::log(LogLevel::VERBOSE, "[Application] Loading Required Resources and Initial Scene.");

    // Load the TTF file into CPU memory (baked at font size 64.0 for crispness)
    if (!mainFont.load("assets/fonts/DejaVuSerif.ttf", 64.0f)) {
        Logger::log(LogLevel::ERROR, "Failed to load main font!");
    }

    // Load the textures into the GPU and save their IDs to the GameState
    gameState.cardTextureId = renderer->loadTexture("assets/cards.png");
    gameState.fontTextureId = renderer->loadTextureFromPixels(mainFont.textureData, mainFont.textureWidth, mainFont.textureHeight);
    // Pure, solid dark gray (RGBA)
    unsigned char darkPixel[4] = {20, 20, 25, 255}; 
    gameState.whiteTextureId = renderer->loadTextureFromPixels(darkPixel, 1, 1);
    
    // Hand the Font pointer to the GameState
    gameState.mainFont = &mainFont;

    // Define the orchestration callback
    gameState.startGameOrchestration = [this]() {
        // The Application owns the processManager and bridge, so it handles the flow
        processManager.initialize([this]() {
            // This inner lambda is the specific connection logic passed to the ProcessManager
            Logger::log(LogLevel::INFO, "[Application] Connecting human player to server...");
            
            // Setup the Main Player
            std::string srv = "tcp://localhost:5555";
            std::string sub = "tcp://localhost:5556";
            std::string user = "Loxas"; 
            std::string pass = "pass";

            gameState.playerName = user;

            // This spawns the C FFI export thread.
            bridge->connectToServer(srv, sub, user, pass);
        });
    };

    // Boot up the first scene
    gameState.currentPhase = GamePhase::NOT_STARTED;
    sceneManager.changeScene<TitleScene>();

    // Simple time tracking for smooth updates
    Uint32 lastTime = SDL_GetTicks();
    
    Logger::log(LogLevel::VERBOSE, "[Application] Entering main loop.");

    isRunning = true;
    while (isRunning) {
        // Check if the bridge died ungracefully
        if (gameState.currentPhase != GamePhase::NOT_STARTED && bridge && !bridge->isAlive()) {
            Logger::log(LogLevel::ERROR, "Lost connection to Haskell Bridge. Cleaning up and returning to Title.");
            
            // Wipe out any lingering server/bot processes
            if (ProcessManager::get()) {
                ProcessManager::get()->terminateAll();
            }

            // Reset the game state
            gameState.currentPhase = GamePhase::NOT_STARTED;
            gameState.cardsOnHand.clear();
            gameState.cardsOnTable.clear();
            
            // Reconstruct the bridge safely (which will join the dead thread)
            bridge = std::make_unique<HaskellBridge>();

            // Swap back to the Title Scene
            sceneManager.changeScene<TitleScene>();
        }

        // Calculate Delta Time (seconds since last frame)
        Uint32 currentTime = SDL_GetTicks();
        float deltaTime = (currentTime - lastTime) / 1000.0f;
        lastTime = currentTime;

        // Handles Input
        handleEvents(); 

        // Update the animation lock timer
        if (gameState.animationLockTimer > 0.0f) {
            gameState.animationLockTimer -= deltaTime;
        }

        // --- THE ACTION DIRECTOR ---
        // Only pull the NEXT command if we are done animating the PREVIOUS one
        if (!gameState.isAnimating()) {
            std::string pendingCmd;
            if (bridge->pollAction(pendingCmd)) {                
                Logger::log(LogLevel::VERBOSE, "[Application] Dispatching command to Scene: ", pendingCmd);
                sceneManager.processCommand(pendingCmd);
            }
        }
        
        // Delegate to the active scene
        sceneManager.update(deltaTime);
        sceneManager.render(renderer.get(), camera);
    }

    // Wait for the GPU to finish its current frame before we destroy the window
    renderer->waitIdle();
}

void Application::handleEvents() {
    SDL_Event event;
    const float panSpeed = 0.05f * camera.zoom; // Move faster when zoomed out

    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) {
            isRunning = false;
        }
        // Catch the window resize event
        if (event.type == SDL_WINDOWEVENT) {
            if (event.window.event == SDL_WINDOWEVENT_RESIZED || event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                renderer->framebufferResized = true;
            }
        }
        // --- CAMERA INPUT ---
        // Mouse Wheel for Zooming
        if (event.type == SDL_MOUSEWHEEL) {
            if (event.wheel.y > 0) camera.zoom *= 0.9f; // Zoom in
            if (event.wheel.y < 0) camera.zoom *= 1.1f; // Zoom out
        }
        // Keyboard for Panning
        if (event.type == SDL_KEYDOWN) {
            switch (event.key.keysym.sym) {
                case SDLK_w: camera.position.y -= panSpeed; break; // Up
                case SDLK_s: camera.position.y += panSpeed; break; // Down
                case SDLK_a: camera.position.x -= panSpeed; break; // Left
                case SDLK_d: camera.position.x += panSpeed; break; // Right
            }
        }

        // Pass any remaining unhandled input (like clicking cards) to the active Scene
        sceneManager.handleInput(event);
    }
}
