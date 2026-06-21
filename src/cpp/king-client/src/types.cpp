#include "king/types.h"
#include <stdexcept>

namespace king {

std::string Card::to_string() const {
    if (suit == Suit::None || rank == Rank::None) {
        return "None";
    }

    std::string result;
    switch (rank) {
        case Rank::Two:   result = "2"; break;
        case Rank::Three: result = "3"; break;
        case Rank::Four:  result = "4"; break;
        case Rank::Five:  result = "5"; break;
        case Rank::Six:   result = "6"; break;
        case Rank::Seven: result = "7"; break;
        case Rank::Eight: result = "8"; break;
        case Rank::Nine:  result = "9"; break;
        case Rank::Ten:   result = "10"; break;
        case Rank::Jack:  result = "J"; break;
        case Rank::Queen: result = "Q"; break;
        case Rank::King:  result = "K"; break;
        case Rank::Ace:   result = "A"; break;
        default:          result = "?"; break;
    }

    switch (suit) {
        case Suit::Spades:   result += "S"; break;
        case Suit::Hearts:   result += "H"; break;
        case Suit::Diamonds: result += "D"; break;
        case Suit::Clubs:    result += "C"; break;
        default:             result += "?"; break;
    }

    return result;
}

Card Card::parse(const std::string& str) {
    if (str.empty() || str == "None") {
        return Card{Suit::None, Rank::None};
    }

    Rank r = Rank::None;
    Suit s = Suit::None;
    char suitChar = '\0';

    if (str.size() == 3 && str.substr(0, 2) == "10") {
        r = Rank::Ten;
        suitChar = str[2];
    } else if (str.size() >= 2) {
        char rankChar = str[0];
        suitChar = str[str.size() - 1]; // Support suit at the very end
        switch (rankChar) {
            case '2': r = Rank::Two; break;
            case '3': r = Rank::Three; break;
            case '4': r = Rank::Four; break;
            case '5': r = Rank::Five; break;
            case '6': r = Rank::Six; break;
            case '7': r = Rank::Seven; break;
            case '8': r = Rank::Eight; break;
            case '9': r = Rank::Nine; break;
            case 'T': r = Rank::Ten; break;
            case 'J': r = Rank::Jack; break;
            case 'Q': r = Rank::Queen; break;
            case 'K': r = Rank::King; break;
            case 'A': r = Rank::Ace; break;
            default:  r = Rank::None; break;
        }
    }

    switch (suitChar) {
        case 'S': s = Suit::Spades; break;
        case 'H': s = Suit::Hearts; break;
        case 'D': s = Suit::Diamonds; break;
        case 'C': s = Suit::Clubs; break;
        default:  s = Suit::None; break;
    }

    return Card{s, r};
}

std::string rule_to_string(Rule rule) {
    switch (rule) {
        case Rule::Vaza:     return "VAZA";
        case Rule::Homens:   return "HOMENS";
        case Rule::Mulheres: return "MULHERES";
        case Rule::TwoLast:  return "2ULTIMAS";
        case Rule::Copas:    return "COPAS";
        case Rule::King:     return "KING";
        case Rule::Positiva: return "POSITIVA";
        default:             return "NONE";
    }
}

Rule string_to_rule(const std::string& s) {
    if (s == "VAZA")     return Rule::Vaza;
    if (s == "HOMENS")   return Rule::Homens;
    if (s == "MULHERES") return Rule::Mulheres;
    if (s == "2ULTIMAS") return Rule::TwoLast;
    if (s == "COPAS")    return Rule::Copas;
    if (s == "KING")     return Rule::King;
    if (s == "POSITIVA") return Rule::Positiva;
    return Rule::None;
}

} // namespace king
