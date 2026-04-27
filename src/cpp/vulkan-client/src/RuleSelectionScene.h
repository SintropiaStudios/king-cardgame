#pragma once
#include "BaseGameScene.h"
#include <vector>
#include <string>

class RuleSelectionScene : public BaseGameScene {
public:
    RuleSelectionScene(SceneManager* mgr, GameState* st);
    
    void onEnter() override;
    void handleInput(const SDL_Event& event) override;
    void render(VulkanRenderer* renderer, Camera& camera) override;

private:
    std::vector<std::string> availableRules;
};
