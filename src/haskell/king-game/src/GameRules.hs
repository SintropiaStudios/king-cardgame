{- HLINT ignore "Redundant if" -}
module GameRules (isValidPlay, evaluateTrick, isHandComplete) where

import KingTypes
    ( KingRule(..)
    , KingCard
    , Card(..)
    , Suit(..)
    , Rank(..), parseCard, unparseCard
    )
import Data.List (elemIndex)
import Data.Maybe (fromJust, isNothing)
import Text.JSON.Parsec (parse)

-- | Evaluates if a card play is valid based on the current rule, table, and hand.
--   Returns True if valid, False otherwise.
isValidPlay :: KingRule -> [KingCard] -> [KingCard] -> KingCard -> Bool
isValidPlay rule table hand card = isValidGenerally table' hand' card' && meetsRuleConstraints rule table' hand' card'
    where   table' = map parseCard table
            hand'  = map parseCard hand
            card'  = parseCard card

-- | General validation logic for following suit, applicable to all rules.
isValidGenerally :: [Card] -> [Card] -> Card -> Bool
isValidGenerally table hand card = case table of
    [] -> True  -- Any card can be played on an empty table
    (ledCard:_) -> let ledSuit = cardSuit ledCard
                    in if any (\c -> cardSuit c == ledSuit) hand
                       then cardSuit card == ledSuit  -- Must follow suit if possible
                       else True  -- Can play any card if void in led suit

-- | Evaluates constraints specific to a given rule.
--   Assumes isValidGenerally has already passed.
meetsRuleConstraints :: KingRule -> [Card] -> [Card] -> Card -> Bool
-- Copas and King: Cannot lead Hearts unless the hand is entirely Hearts
meetsRuleConstraints rule [] hand card
    | rule `elem` [RCopas, RKing] =
        cardSuit card /= Hearts || all (\c -> cardSuit c == Hearts) hand
    | otherwise = True
-- King: If discarding (void in led suit), and holding the King of Hearts, it must be played
meetsRuleConstraints RKing (ledCard:_) hand card =
    let ledSuit = cardSuit ledCard
        isVoid = not (any (\c -> cardSuit c == ledSuit) hand)
    in (not (isVoid && kingOfHearts `elem` hand) || (card == kingOfHearts))
    where kingOfHearts = Card King Hearts

-- All other rules and situations have no extra constraints
meetsRuleConstraints _ _ _ _ = True

type RoundCount = Int  -- Placeholder for round count tracking

-- | Evaluates the cards on a table given a Rule, returns round winner and their score
evaluateTrick :: KingRule -> RoundCount -> [KingCard] -> (Int, Int)
evaluateTrick rule round cards =
    let cards' = map parseCard cards
        ledSuit = cardSuit (head cards')
        -- Determine the winner of the trick based on the led suit and any trumps
        winnerIndex = determineWinner rule ledSuit cards'
        -- Calculate score based on the rule and round count
        score = calculateScore rule round cards'
    in (winnerIndex, score)

getPositivaSuit :: KingRule -> Maybe Suit
getPositivaSuit r = case r of
    RPositivaH -> Just Hearts
    RPositivaS -> Just Spades
    RPositivaD -> Just Diamonds
    RPositivaC -> Just Clubs
    _ -> Nothing

determineWinner :: KingRule -> Suit -> [Card] -> Int
determineWinner rule ledSuit cards
    | Just trump <- getPositivaSuit rule = if any (\c -> cardSuit c == trump) cards
        then determineHighestOfSuit trump cards
        else determineHighestOfSuit ledSuit cards
    | otherwise = determineHighestOfSuit ledSuit cards

determineHighestOfSuit :: Suit -> [Card] -> Int
determineHighestOfSuit suit cards =
    let cardsOfSuit = filter (\c -> cardSuit c == suit) cards
        highestCard = maximum cardsOfSuit
    in fromJust (elemIndex highestCard cards)

calculateScore :: KingRule -> RoundCount -> [Card] -> Int
calculateScore rule round cards = case rule of
    RVaza -> -20
    RMulheres -> -(50 * length (filter (\c -> cardRank c == Queen) cards))
    RHomens -> -(30 * length (filter (\c -> cardRank c == King || cardRank c == Jack) cards))
    R2Ultimas -> if round >= 12 then -90 else 0
    RCopas -> -(20 * length (filter (\c -> cardSuit c == Hearts) cards))
    RKing -> if Card King Hearts `elem` cards then -160 else 0
    _ -> 25 -- Positivas always award 25

-- | Determines if a hand is mathematically over based on the remaining cards in play.
isHandComplete :: KingRule -> [KingCard] -> Bool
isHandComplete rule remainingCards = case rule of
    RKing     -> "KH" `notElem` remainingCards
    RMulheres -> not $ any (\(c:cs) -> c == 'Q') remainingCards
    RHomens   -> not $ any (\(c:cs) -> c == 'J' || c == 'K') remainingCards
    RCopas    -> not $ any (\c -> last c == 'H') remainingCards
    _         -> null remainingCards -- VAZA, 2ULTIMAS, POSITIVA must play to 0 cards
