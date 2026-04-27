#pragma once
#include "Scene.h"

struct UIButton {
    std::string ruleCommand; // e.g., "POSITIVA"
    std::string displayText; // e.g., "POSITIVA (1)"
    SDL_Keycode shortcutKey;
    float x, y, width, height; // World coordinates for mouse clicks
    bool isHovered = false;
};

class RenderBatch;

class BaseGameScene : public Scene {
public:
    BaseGameScene(SceneManager* mgr, GameState* st);
    virtual ~BaseGameScene() = default;

    // Implement the update loop here to parse Haskell messages for ALL child scenes    
    virtual void handleInput(const SDL_Event&) override {};
    virtual void update(float deltaTime) override;    
    virtual void render(VulkanRenderer* renderer, Camera& camera) override;

    // Implement the base processing to handle scene transitions
    virtual void processCommand(const std::string& cmd) override;

protected:
    constexpr static float fontScale = 0.001f; 
    constexpr static float paddingX = 0.04f; 
    constexpr static float paddingY = 0.02f;

    std::vector<UIButton> buttons;
    
    // Add UI Buttons to Render Batch
    bool renderUIButtons(RenderBatch& batchGeometry, RenderBatch& batchText);

    // Helper to generate the vertices for the solid background boxes
    void addSolidQuad(std::vector<Vertex>& batch, float x, float y, float w, float h);

    void recalculateHandLayout();
    void recalculateTableLayout();

    void getNewHand();
};
