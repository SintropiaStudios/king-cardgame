#pragma once
#include <SDL2/SDL.h>
#include "VulkanRenderer.h"
#include "Camera.h"
#include "GameState.h"
#include <string>

// Forward declaration so scenes can change the active scene
class SceneManager; 

class Scene {
protected:
    SceneManager* manager;
    GameState*    state;
public:
    Scene(SceneManager* mgr, GameState* st) : manager(mgr), state(st) {}
    virtual ~Scene() = default;
    
    // Lifecycle hooks
    virtual void onEnter() {};
    virtual void onExit() {};
    
    // Core loop hooks
    virtual void handleInput(const SDL_Event& event) = 0;
    virtual void update(float deltaTime) = 0;
    virtual void render(VulkanRenderer* renderer, Camera& camera) = 0;

    // The callback target for our command dispatcher
    virtual void processCommand(const std::string& cmd) {};
};
