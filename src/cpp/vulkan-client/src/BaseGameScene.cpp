#include "BaseGameScene.h"
#include <SDL2/SDL_vulkan.h>

#include "InGameScene.h"
#include "RuleSelectionScene.h"

#include "SceneManager.h"
#include "Logger.h"

#include <sstream>
#include <algorithm>
#include <string>
#include <optional>

BaseGameScene::BaseGameScene(SceneManager* mgr, GameState* st) : Scene(mgr, st) {}

std::optional<size_t> getPlayerIndex(GameState& state, std::string_view name) {
    auto it = std::find_if( state.players.begin(), state.players.end(),
                            [&name](const Player& p) { return p.name == name; });

    if (it != state.players.end()) {
        return std::distance(state.players.begin(), it);
    }

    return std::nullopt;
}

void BaseGameScene::render(VulkanRenderer* renderer, Camera& camera) {
    std::vector<RenderBatch> batches;

    // Maybe render the Score, this is more of a fallback though
    int width, height;
    SDL_Vulkan_GetDrawableSize(renderer->getWindow(), &width, &height);
    glm::mat4 viewProj = camera.getViewProjectionMatrix((float)width, (float)height);

    renderer->drawFrame(batches, viewProj);
}

bool BaseGameScene::renderUIButtons(RenderBatch& uiBoxBatch, RenderBatch& textBatch){
    bool ret = false;

    for (const auto& btn : buttons) {
        addSolidQuad(uiBoxBatch.vertices, btn.x, btn.y, btn.width, btn.height);
        
        float textX = btn.x + paddingX;
        
        // Push the typographic baseline down to center it vertically
        float textHeight = btn.height - (paddingY * 2.0f);
        float textY = btn.y + paddingY + (textHeight * 0.8f); 
        
        state->mainFont->addTextToBatch(textBatch.vertices, btn.displayText, textX, textY, fontScale);
        ret = true;
    }

    uiBoxBatch.textureId = state->whiteTextureId; // Now a solid dark pixel
    textBatch.textureId = state->fontTextureId;
    return ret;
}

void BaseGameScene::addSolidQuad(std::vector<Vertex>& batch, float x, float y, float w, float h) {
    // We sample the exact center of our 1x1 pixel texture
    float u = 0.5f, v = 0.5f;
    batch.push_back({{x, y}, {u, v}});
    batch.push_back({{x + w, y}, {u, v}});
    batch.push_back({{x + w, y + h}, {u, v}});
    batch.push_back({{x + w, y + h}, {u, v}});
    batch.push_back({{x, y + h}, {u, v}});
    batch.push_back({{x, y}, {u, v}});
}

void BaseGameScene::recalculateHandLayout() {
    if (state->cardsOnHand.empty()) return;
    
    float spacing = 0.18f;
    float totalWidth = (state->cardsOnHand.size() - 1) * spacing;
    float startX = -(totalWidth / 2.0f);
    float yPos = 0.7f; // Bottom of screen

    for (auto& card : state->cardsOnHand) {
        card.x = startX;
        card.y = yPos;
        startX += spacing;
    }
}

void BaseGameScene::recalculateTableLayout() {
    if (state->cardsOnTable.empty()) return;
    
    float spacing = 0.2f;
    float totalWidth = (state->cardsOnTable.size() - 1) * spacing;
    float startX = -(totalWidth / 2.0f);
    float yPos = 0.0f; // Dead center of the table

    for (auto& card : state->cardsOnTable) {
        card.x = startX;
        card.y = yPos;
        startX += spacing;
    }
}

void BaseGameScene::update(float deltaTime) {
}

void BaseGameScene::processCommand(const std::string& cmd) {
    // Updates from Server, no Action requested
    if (cmd.rfind("KUpdate ", 0) == 0) {
        std::istringstream iss(cmd);
        std::string kupdate, tableId, eventType;
        iss >> kupdate >> tableId >> eventType;

        if (eventType == "START") {
            // Pause the engine so the player can see the move
            auto& players = state->players;
            Logger::log(LogLevel::INFO, "[Base Scene Update] New Table Started");
            for (int i = 0; i < 4; i++) {
                iss >> players[i].name;
                if (state->playerName == players[i].name) {
                    state->ourPlayerIndex = i;
                }
            }

            state->animationLockTimer = 0.5f; 
        } else if (eventType == "PLAY") {
            std::string cardId;
            iss >> cardId;
            Logger::log(LogLevel::INFO, "[Base Scene] Card played: ", cardId);

            // A. If *we* played this card, remove it from our local hand!
            auto it = std::find_if(state->cardsOnHand.begin(), state->cardsOnHand.end(),
                                   [&cardId](const Card& c) { return c.id == cardId; });
            if (it != state->cardsOnHand.end()) {
                state->currentPhase = GamePhase::TRICK_PLAYING;
                state->cardsOnHand.erase(it);
                recalculateHandLayout(); // Slide hand together
            }

            // B. Add the card to the table
            state->cardsOnTable.emplace_back(cardId, 0.0f, 0.0f); // X/Y don't matter yet
            recalculateTableLayout(); // Centers all table cards perfectly

            // C. Pause the engine so the player can see the move
            state->animationLockTimer = 1.0f; 
        } else if (eventType == "TURN") {    
            std::string playerTurn;
            iss >> playerTurn;

            Logger::log(LogLevel::INFO, "[BaseScene] Turn is now with ", playerTurn);
            if (auto playerIndex = getPlayerIndex(*state, playerTurn)) {
                state->currentPlayerTurn = *playerIndex;
            } else {
                Logger::log(LogLevel::WARNING, "[BaseScene] Informed Player for Turn not found. Re-syncing State.");
            }            
        } else if (eventType == "STARTHAND") {
            std::string startPlayer;
            iss >> startPlayer;
            
            // Identifies who starts the hand
            Logger::log(LogLevel::INFO, "[BaseScene] A new hand has started, starting with ", startPlayer);
            if (auto playerIndex = getPlayerIndex(*state, startPlayer)) {
                state->startingPlayerIndex = *playerIndex;
            } else {
                Logger::log(LogLevel::WARNING, "[BaseScene] Informed Player for Hand not found. Re-syncing State.");
            }

            // Initialize a new score for this hand
            for (auto& p : state->players) {
                p.scores.push_back(0);
            }

            // In case this is not the player's turn, collect his hand cards
            if (state->currentPhase == GamePhase::WAITING_FOR_RULE) {
                Logger::log(LogLevel::INFO, "[BaseScene] Collecting hand.");
                // When a new hand starts, we need a heavy FFI pull as hand is never broadcasted 
                getNewHand();
            }
        } else if (eventType == "GAME") {
            std::string activeRule;
            iss >> activeRule;
            state->activeRule = activeRule;

            Logger::log(LogLevel::INFO, "[BaseScene] Game will be ", activeRule);
            if (state->currentPhase == GamePhase::WAITING_FOR_RULE) {
                Logger::log(LogLevel::INFO, "[BaseScene] Moving to Play Screen.");
                // Transition fom Rule Selection to Play
                state->currentPhase = GamePhase::TRICK_PLAYING;
                manager->changeScene<InGameScene>();
            }
        } else if (eventType == "ENDROUND") {
            // Trick has ended, clears the table
            // Extract winner and score
            std::string winner;
            int score;
            iss >> winner >> score;
            Logger::log(LogLevel::INFO, "[BaseScene] Trick won by: ", winner, ", score: ", score);

            // Update score
            if (auto playerIndex = getPlayerIndex(*state, winner)) {
                auto curScore = state->players[*playerIndex].scores.rbegin();
                *curScore += score;
            } else {
                Logger::log(LogLevel::WARNING, "[BaseScene] Informed Player for Turn not found. Re-syncing State.");
            }

            // Clear the table for the next trick
            state->cardsOnTable.clear();
            
            // Pause longer so the player registers who took the cards
            state->animationLockTimer = 2.0f;
        } else if (eventType == "ENDHAND") {
            // Hand is over ... update score table
            Logger::log(LogLevel::INFO, "[BaseScene] Hand Ended: ", cmd);
            
            state->currentPhase = GamePhase::WAITING_FOR_RULE;

            // Pause for 3 seconds so the player can see final score
            state->animationLockTimer = 3.0f;
        } else if (eventType == "GAMEOVER") {
            // Game is over ... maybe just present score table and button to restart
            Logger::log(LogLevel::INFO, "[BaseScene] Game Ended: ", cmd);
        }

        return; 
    }

    // Action Requested
    if (cmd == "KRule") {
        Logger::log(LogLevel::INFO, "[BaseScene] Server requested Rule Selection");
        state->currentPhase = GamePhase::CHOOSE_RULE;
        
        // When a new hand starts, we need a heavy FFI pull as hand is never broadcasted 
        getNewHand();
        manager->changeScene<RuleSelectionScene>();
        // The scene will now know to draw the rule selection buttons
    } 
    else if (cmd == "KPlay") {
        Logger::log(LogLevel::INFO, "[BaseScene] Server requested Play Selection!");

        // Possibly this appears before Rule is set
        if (state->currentPhase != GamePhase::CHOOSE_PLAY) {
            manager->changeScene<InGameScene>();
        }

        state->currentPhase = GamePhase::CHOOSE_PLAY;
    }
    else if (cmd == "KBid") {
        state->currentPhase = GamePhase::AUCTION_BIDDING;
    }
    // ... Handle other commands ...
}

void BaseGameScene::getNewHand() {
    if (state->getPlayerHand) {
        std::vector<std::string> rawCards = state->getPlayerHand();
        state->cardsOnHand.clear();
        for (const auto& cardId : rawCards) {
            state->cardsOnHand.emplace_back(cardId, 0.0f, 0.0f);
        }
        recalculateHandLayout();
    }
}
