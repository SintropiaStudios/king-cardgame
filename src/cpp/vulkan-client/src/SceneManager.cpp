#include "SceneManager.h"

void SceneManager::changeScene(std::unique_ptr<Scene> newScene) {
    // Queue the scene change safely
    nextScene = std::move(newScene);
}

void SceneManager::handleInput(const SDL_Event& event) {
    if (currentScene) currentScene->handleInput(event);
}

void SceneManager::update(float deltaTime) {
    // Process any queued scene changes before updating
    if (nextScene) {
        if (currentScene) {
            currentScene->onExit();
        }
        currentScene = std::move(nextScene);
        currentScene->onEnter();
    }

    if (currentScene) currentScene->update(deltaTime);
}

void SceneManager::render(VulkanRenderer* renderer, Camera& camera) {
    if (currentScene) currentScene->render(renderer, camera);
}

void SceneManager::processCommand(const std::string& cmd) {
    if (currentScene) currentScene->processCommand(cmd);
}
