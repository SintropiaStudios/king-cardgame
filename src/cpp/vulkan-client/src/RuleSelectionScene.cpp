#include "RuleSelectionScene.h"
#include <SDL2/SDL_vulkan.h>

#include "SceneManager.h"
#include "Logger.h"

RuleSelectionScene::RuleSelectionScene(SceneManager* mgr, GameState* st) 
    : BaseGameScene(mgr, st) {}

void RuleSelectionScene::onEnter() {
    Logger::log(LogLevel::INFO, "[Scene Transition] Entered Rule Selection GUI");
    buttons.clear();

    if (state->getAvailableRules) {
        std::vector<std::string> rules = state->getAvailableRules();
        
        float marginX = 0.05f;  
        float marginY = 0.05f;  
        
        float startX = -0.7f;   
        float startY = -0.6f;   
        float currentX = startX;
        float currentY = startY;
        float maxRowHeight = 0.0f;
        float screenLimitX = 0.7f; // Wrap earlier to leave a right margin

        int shortcutNumber = 1;

        for (const auto& rule : rules) {
            UIButton btn;
            btn.ruleCommand = rule;
            btn.displayText = rule + " (" + std::to_string(shortcutNumber) + ")";

            float txtW, txtH;
            state->mainFont->getTextBounds(btn.displayText, fontScale, txtW, txtH);

            btn.width = txtW + (paddingX * 2.0f);
            btn.height = txtH + (paddingY * 2.0f);
            
            // Grid Wrapping Logic
            if (currentX + btn.width > screenLimitX && currentX > startX) {
                currentX = startX;
                currentY += maxRowHeight + marginY;
                maxRowHeight = 0.0f;
            }

            btn.x = currentX;
            btn.y = currentY;

            if (shortcutNumber <= 9) btn.shortcutKey = SDLK_1 + (shortcutNumber - 1);
            else btn.shortcutKey = SDLK_UNKNOWN;

            buttons.push_back(btn);
            
            currentX += btn.width + marginX;
            if (btn.height > maxRowHeight) maxRowHeight = btn.height;
            shortcutNumber++;
        }
    }
}

void RuleSelectionScene::handleInput(const SDL_Event& event) {
    // 1. KEYBOARD SHORTCUTS
    if (event.type == SDL_KEYDOWN) {
        for (const auto& btn : buttons) {
            if (event.key.keysym.sym == btn.shortcutKey) {
                Logger::log(LogLevel::INFO, "Rule selected via shortcut: ", btn.ruleCommand);
                
                // Fire the action to Haskell!
                if (state->submitAction) {
                    std::string action = std::string("GAME ") + btn.ruleCommand;
                    state->submitAction(action);
                }
                
                // Clear buttons to prevent double-firing
                buttons.clear(); 
                return;
            }
        }
    }

    // 2. MOUSE CLICKS (AABB Collision)
    if (event.type == SDL_MOUSEBUTTONDOWN && event.button.button == SDL_BUTTON_LEFT) {
        // NOTE: You will need to convert event.button.x / y from Screen Space (Pixels) 
        // to World Space (-1.0 to 1.0) based on your Camera matrix to check intersection!
        
        // float mouseWorldX = ...
        // float mouseWorldY = ...
        // if (mouseWorldX >= btn.x && mouseWorldX <= btn.x + btn.width && ...)
    }
}

void RuleSelectionScene::render(VulkanRenderer* renderer, Camera& camera) {
    std::vector<RenderBatch> batches;

    // Render The Rules
    RenderBatch uiBoxBatch, textBatch;
    if (renderUIButtons(uiBoxBatch, textBatch)) {
        batches.push_back(uiBoxBatch);
        batches.push_back(textBatch);
    }

    // Render Cards at the Bottom
    RenderBatch cardBatch;
    cardBatch.textureId = state->cardTextureId; // Use the ID from GameState
    for (const auto& card : state->cardsOnHand) {
        card.addVertices(cardBatch.vertices);
    }
    if (!cardBatch.vertices.empty()) {
        batches.push_back(cardBatch);
    }

    // --- SUBMIT TO VULKAN ---
    int width, height;
    SDL_Vulkan_GetDrawableSize(renderer->getWindow(), &width, &height);
    glm::mat4 viewProj = camera.getViewProjectionMatrix((float)width, (float)height);
    
    // Pass the grouped batches to the new rendering pipeline!
    renderer->drawFrame(batches, viewProj);
}
