#pragma once

#include <string>
#include <vector>

namespace king {

enum class Suit : uint8_t {
    Spades = 0,
    Hearts,
    Diamonds,
    Clubs,
    None
};

enum class Rank : uint8_t {
    Two = 2, Three, Four, Five, Six, Seven, Eight, Nine, Ten,
    Jack, Queen, King, Ace, None
};

struct Card {
    Suit suit = Suit::None;
    Rank rank = Rank::None;

    bool operator==(const Card& other) const {
        return suit == other.suit && rank == other.rank;
    }

    std::string to_string() const;
    static Card parse(const std::string& str);
};

enum class Rule {
    Vaza,
    Homens,
    Mulheres,
    TwoLast,
    Copas,
    King,
    Positiva,
    None
};

std::string rule_to_string(Rule rule);
Rule string_to_rule(const std::string& s);

struct Table {
    std::string name; // UUID
    std::vector<std::string> players;
};

enum class GamePhase {
    Offline,
    Connecting,
    Lobby,
    Bidding,
    Playing,
    Scoring,
    GameOver
};

} // namespace king
