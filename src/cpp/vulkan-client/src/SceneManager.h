#pragma once
#include <memory>
#include "Scene.h"
#include "GameState.h"

class SceneManager {
public:
    SceneManager(GameState* st) : state(st) {}

    template <typename T>
    void changeScene() { changeScene(std::make_unique<T>(this, state)); }

    void changeScene(std::unique_ptr<Scene> newScene);
    void handleInput(const SDL_Event& event);
    void update(float deltaTime);
    void render(VulkanRenderer* renderer, Camera& camera);

    void processCommand(const std::string& cmd);

private:
    GameState*      state;

    std::unique_ptr<Scene> currentScene;
    std::unique_ptr<Scene> nextScene; // Holds the requested scene until it's safe to swap
};