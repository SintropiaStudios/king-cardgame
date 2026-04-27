#include "Card.h"

Card::Card(const std::string& cardId, float startX, float startY) 
    : id(cardId), x(startX), y(startY) {
    
    // 1. Handle Card Backs
    if (cardId == "BACK" || cardId.empty()) {
        rank = Rank::_BACK;
        suit = Suit::HIDDEN;
        atlasCol = 0; // Adjust to wherever your card back lives in the texture!
        atlasRow = 4; 
        return;
    }

    // 2. Parse the Suit (Always the last character)
    char suitChar = cardId.back();
    switch (suitChar) {
        case 'C': suit = Suit::CLUBS;    atlasRow = 0; break;
        case 'D': suit = Suit::DIAMONDS; atlasRow = 1; break;
        case 'H': suit = Suit::HEARTS;   atlasRow = 2; break;
        case 'S': suit = Suit::SPADES;   atlasRow = 3; break;
        default:  suit = Suit::HIDDEN;   atlasRow = 4; break;
    }

    // 3. Parse the Rank (Everything before the suit character)
    std::string rankStr = cardId.substr(0, cardId.size() - 1);
    
    if (rankStr == "A")      { rank = Rank::_A;  atlasCol = 0; }
    else if (rankStr == "2") { rank = Rank::_2;  atlasCol = 1; }
    else if (rankStr == "3") { rank = Rank::_3;  atlasCol = 2; }
    else if (rankStr == "4") { rank = Rank::_4;  atlasCol = 3; }
    else if (rankStr == "5") { rank = Rank::_5;  atlasCol = 4; }
    else if (rankStr == "6") { rank = Rank::_6;  atlasCol = 5; }
    else if (rankStr == "7") { rank = Rank::_7;  atlasCol = 6; }
    else if (rankStr == "8") { rank = Rank::_8;  atlasCol = 7; }
    else if (rankStr == "9") { rank = Rank::_9;  atlasCol = 8; }
    else if (rankStr == "10"){ rank = Rank::_10; atlasCol = 9; }
    else if (rankStr == "J") { rank = Rank::_J;  atlasCol = 10; }
    else if (rankStr == "Q") { rank = Rank::_Q;  atlasCol = 11; }
    else if (rankStr == "K") { rank = Rank::_K;  atlasCol = 12; }
}

void Card::addVertices(std::vector<Vertex>& batch) const {
    float width = 0.32f; 
    float height = 0.5f;
    float uvWidth = 1.0f / 13.0f; 
    float uvHeight = 1.0f / 5.0f;
    
    float uStart = atlasCol * uvWidth; 
    float uEnd = (atlasCol + 1) * uvWidth;
    float vStart = atlasRow * uvHeight; 
    float vEnd = (atlasRow + 1) * uvHeight;

    batch.push_back({{x - width, y - height}, {uStart, vStart}});
    batch.push_back({{x + width, y - height}, {uEnd,   vStart}});
    batch.push_back({{x + width, y + height}, {uEnd,   vEnd}});
    batch.push_back({{x + width, y + height}, {uEnd,   vEnd}});
    batch.push_back({{x - width, y + height}, {uStart, vEnd}});
    batch.push_back({{x - width, y - height}, {uStart, vStart}});
}
