{-# LANGUAGE InstanceSigs #-}
module KingTypes
    ( KingRule(..)
    , readRule
    , startingRules
    , isPositiva
    , allNegativeRules
    , KingCard
    , KingSuit
    , Card(..)
    , Suit(..)
    , Rank(..)
    , parseCard
    , unparseCard
    )
    where

data KingRule = RVaza | RMulheres | RHomens | RKing | RCopas | R2Ultimas |
                RPositiva | RPositivaH | RPositivaS | RPositivaD | RPositivaC
    deriving Eq

instance Show KingRule where
    show :: KingRule -> String
    show r = case r of
        RVaza       -> "VAZA"
        RHomens     -> "HOMENS"
        RMulheres   -> "MULHERES"
        R2Ultimas   -> "2ULTIMAS"
        RCopas      -> "COPAS"
        RKing       -> "KING"
        _           -> "POSITIVA" -- Defaults to Positiva for all Positiva variants

readRule :: String -> KingRule
readRule rule = case rule of 
    m | m == "VAZA"      -> RVaza
    m | m == "HOMENS"    -> RHomens
    m | m == "MULHERES"  -> RMulheres
    m | m == "2ULTIMAS"  -> R2Ultimas
    m | m == "COPAS"     -> RCopas
    m | m == "KING"      -> RKing
    m | m == "POSITIVAH" -> RPositivaH
    m | m == "POSITIVAC" -> RPositivaC
    m | m == "POSITIVAS" -> RPositivaS
    m | m == "POSITIVAD" -> RPositivaD
    _ -> RPositiva  -- Default to generic Positiva if unknown rule is encountered

-- | Helper to check if a rule is a Positiva variant
isPositiva :: KingRule -> Bool
isPositiva r = r `elem` [RPositiva, RPositivaH, RPositivaC, RPositivaS, RPositivaD]

-- A helper defining the standard starting rules for a player based on king.py
startingRules :: [KingRule]
startingRules = [RVaza, RHomens, RMulheres, R2Ultimas, RCopas, RKing, RPositiva]

-- | All negative rules in the game
allNegativeRules :: [KingRule]
allNegativeRules = [RVaza, RHomens, RMulheres, R2Ultimas, RCopas, RKing]

type KingCard = String
type KingSuit = Char

-- Deriving Enum and Bounded is handy for iterating over a deck.
-- Ording of Rank and Suit is crucial for determining trick winners. (arbitrary in the case of Suits)
data Suit = Clubs | Diamonds | Hearts | Spades 
    deriving (Eq, Ord, Show, Enum, Bounded)

-- The order of constructors dictates the 'Ord' derivation. 
-- R2 is the lowest, Ace is the highest. This replaces Python's RANKS.index()
data Rank = R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | R10 | Jack | Queen | King | Ace 
    deriving (Eq, Ord, Show, Enum, Bounded)

data Card = Card { cardRank :: Rank, cardSuit :: Suit } 
    deriving (Eq, Ord, Show)

-- | Converts the wire string format (e.g., "TC", "AH") into our robust ADT
parseCard :: KingCard -> Card
parseCard ['1', '0', s] = Card R10 (parseSuit s)    -- Legacy support
parseCard [r, s] = Card (parseRank r) (parseSuit s)
  where
    parseRank '2' = R2
    parseRank '3' = R3
    parseRank '4' = R4
    parseRank '5' = R5
    parseRank '6' = R6
    parseRank '7' = R7
    parseRank '8' = R8
    parseRank '9' = R9
    parseRank 'T' = R10
    parseRank 'J' = Jack
    parseRank 'Q' = Queen
    parseRank 'K' = King
    parseRank 'A' = Ace
    parseRank _   = error "Invalid Rank"
parseCard _ = error "Invalid Card Format"

parseSuit :: Char -> Suit
parseSuit 'C' = Clubs
parseSuit 'D' = Diamonds
parseSuit 'H' = Hearts
parseSuit 'S' = Spades
parseSuit _   = error "Invalid Suit"

-- | Converts our ADT back to the wire format if needed
unparseCard :: Card -> KingCard
unparseCard (Card r s) = rankStr r ++ suitStr s
  where
    rankStr R2 = "2"; rankStr R3 = "3"; rankStr R4 = "4"; rankStr R5 = "5"
    rankStr R6 = "6"; rankStr R7 = "7"; rankStr R8 = "8"; rankStr R9 = "9"
    rankStr R10 = "10"; rankStr Jack = "J"; rankStr Queen = "Q"; rankStr King = "K"; rankStr Ace = "A"
    
    suitStr Clubs = "C"; suitStr Diamonds = "D"; suitStr Hearts = "H"; suitStr Spades = "S"
