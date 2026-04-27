#include "InGameScene.h"
#include <SDL2/SDL_vulkan.h>

#include "SceneManager.h"
#include "Logger.h"

#include <algorithm>
#include <vector>

InGameScene::InGameScene(SceneManager* mgr, GameState* st) : BaseGameScene(mgr, st) {}

void InGameScene::onEnter() {
    Logger::log(LogLevel::INFO, "[Scene Transition] Entered In-Game Scene.");
}

void InGameScene::handleInput(const SDL_Event& event) {
    // Only allow clicking cards if it's actually our turn!
    if ((state->currentPhase != GamePhase::CHECKING_PLAY
        && state->currentPhase != GamePhase::CHOOSE_PLAY)
        || winWidth == 0 || winHeight == 0) {
        return; 
    }

    if (event.type == SDL_MOUSEBUTTONDOWN && event.button.button == SDL_BUTTON_LEFT) {
        // Grab the mouse pixel coordinates
        int mouseX = event.button.x;
        int mouseY = event.button.y;

        // --- CONVERT PIXELS TO VULKAN WORLD SPACE ---
        // 1. Normalize to 0.0 -> 1.0
        float normX = static_cast<float>(mouseX) / winWidth;
        float normY = static_cast<float>(mouseY) / winHeight;

        // 2. Map to Vulkan NDC (-1.0 to 1.0)
        float ndcX = (normX * 2.0f) - 1.0f;
        float ndcY = (normY * 2.0f) - 1.0f;

        // 3. Account for your Camera's Aspect Ratio (assuming a standard Ortho setup)
        float aspectRatio = static_cast<float>(winWidth) / static_cast<float>(winHeight);
        float worldX = ndcX * aspectRatio; 
        float worldY = ndcY; // Assuming Y is -1 to 1

        // --- AABB COLLISION DETECTION ---
        // We iterate backwards so we check the cards drawn "on top" first
        for (auto it = state->cardsOnHand.rbegin(); it != state->cardsOnHand.rend(); ++it) {
            const Card& card = *it;
            
            // These match the half-widths defined in Card::addVertices
            float cardHalfWidth = 0.32f; 
            float cardHalfHeight = 0.5f;

            // Check if the world-space mouse is inside the card's bounding box
            if (worldX >= card.x - cardHalfWidth && worldX <= card.x + cardHalfWidth &&
                worldY >= card.y - cardHalfHeight && worldY <= card.y + cardHalfHeight) {
                
                Logger::log(LogLevel::INFO, "[InGameScene] Card Clicked! Sending to Haskell: ", card.id);

                // Fire the action over the ZeroMQ bridge!
                if (state->submitAction) {
                    state->currentPhase = GamePhase::CHECKING_PLAY;
                    std::string action = std::string("PLAY ") + card.id;
                    state->submitAction(action);
                }

                // Prevent a single click from hitting multiple overlapping cards
                break; 
            }
        }
    }
}

void InGameScene::render(VulkanRenderer* renderer, Camera& camera) {
    std::vector<RenderBatch> batches;

    // --- CARDS ---
    RenderBatch cardBatch;
    cardBatch.textureId = state->cardTextureId; // Use the ID from GameState!

    for (const auto& card : state->cardsOnHand) {
        card.addVertices(cardBatch.vertices);
    }
    for (const auto& card : state->cardsOnTable) {
        card.addVertices(cardBatch.vertices);
    }
    
    // Only submit the batch if there's actually something to draw
    if (!cardBatch.vertices.empty()) {
        batches.push_back(cardBatch);
    }

    SDL_Vulkan_GetDrawableSize(renderer->getWindow(), &winWidth, &winHeight);
    glm::mat4 viewProj = camera.getViewProjectionMatrix((float)winWidth, (float)winHeight);
    
    // Pass the grouped batches to the new rendering pipeline!
    renderer->drawFrame(batches, viewProj);
}

void InGameScene::update(float deltaTime) {
    BaseGameScene::update(deltaTime);
}

void InGameScene::processCommand(const std::string& cmd) {    
    // Allow Base Scene to process initial commands and transitions
    BaseGameScene::processCommand(cmd);
}
