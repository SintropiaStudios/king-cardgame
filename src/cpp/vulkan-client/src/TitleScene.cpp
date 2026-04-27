#include "TitleScene.h"
#include <SDL2/SDL_vulkan.h>

#include "SceneManager.h"
#include "BaseGameScene.h" // We will transition to this!
#include "Logger.h"

#include <memory>
#include <thread>
#include <chrono>

TitleScene::TitleScene(SceneManager* mgr, GameState* st) 
    : Scene(mgr, st) {}

void TitleScene::onEnter() {
    Logger::log(LogLevel::INFO, "[Title Scene] Press ENTER or Click to Start.");
    // (Later, we will draw the game logo here)
    state->currentPhase = GamePhase::NOT_STARTED;
}

void TitleScene::onExit() {
    Logger::log(LogLevel::INFO, "[Title Scene] Starting Match Orchestration...");
    
    // Launch the Game
    if (state->startGameOrchestration) {
        // Move the C++ State Machine forward
        state->currentPhase = GamePhase::INITIALIZING;
        state->startGameOrchestration();
    }
}

void TitleScene::handleInput(const SDL_Event& event) {
    if ((event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_RETURN) ||
        (event.type == SDL_MOUSEBUTTONDOWN)) {
        
        // Transition to Next Scene
        manager->changeScene<BaseGameScene>();
    }
}

void TitleScene::update(float deltaTime) {
    // Idle animation logic for the title screen goes here
}

void TitleScene::render(VulkanRenderer* renderer, Camera& camera) {
    // For now, we just pass an empty vertex array so it draws the blank green screen
    std::vector<RenderBatch> emptyBatch;
    
    int width, height;
    SDL_Vulkan_GetDrawableSize(renderer->getWindow(), &width, &height);
    glm::mat4 viewProj = camera.getViewProjectionMatrix((float)width, (float)height);

    renderer->drawFrame(emptyBatch, viewProj);
}
