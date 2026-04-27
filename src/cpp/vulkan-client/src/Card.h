#pragma once
#include <string>
#include <vector>
#include "VulkanRenderer.h" // Needed for the Vertex struct

enum class Suit {
    CLUBS,
    DIAMONDS,
    HEARTS,
    SPADES,
    NO_TRUMP,
    HIDDEN // Used for card backs
};

enum class Rank {    
    _BACK = -1,
    _2 = 2, _3, _4, _5, _6, _7, _8, _9, _10,
    _J, _Q, _K, _A
};

class Card {
public:
    Rank rank;
    Suit suit;
    float x, y;
    int atlasCol;
    int atlasRow;
    std::string id; // Keep the original string (e.g., "2H") handy for sending back to Haskell!

    // The constructor handles all parsing and atlas coordinate generation
    Card(const std::string& cardId, float startX, float startY);

    // The card generates its own geometry!
    void addVertices(std::vector<Vertex>& batch) const;
};
