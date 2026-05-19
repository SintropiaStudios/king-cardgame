{-# LANGUAGE OverloadedStrings #-}
module KingAgent
    ( SmartBot(..)
    ) where

import Data.List (maximumBy, sortBy, find, delete, elemIndex)
import Data.Ord (comparing)
import Data.Maybe (fromMaybe, isJust)
import qualified Data.ByteString.Char8 as BS

import KingTypes
import KingClient
import BaseClient (ContextAwareAgent(..))
import GameRules (isValidPlay)

----------------------------------------------------------------------------------
-- 1. Bot Personality & State
----------------------------------------------------------------------------------

data SmartBot = SmartBot
    { botName      :: String
    , riskAversion :: Float  -- 0.0 (Aggressive) to 1.0 (Safe)
    , socialLevel  :: Float  -- 0.0 (Individualistic) to 1.0 (Table-Aware)
    } deriving (Show, Eq)

personalityAlice :: SmartBot
personalityAlice = SmartBot "Alice" 0.3 0.8  -- Aggressive and aware

personalityBob :: SmartBot
personalityBob = SmartBot "Bob" 0.8 0.2    -- Safe and individualistic

instance ContextAwareAgent SmartBot where
    decideAction action game bot = do
        let decisionStr = case action of
                KRule   -> pickSmartRule game bot
                KPlay   -> pickSmartCard game bot
                KBid    -> pickSmartBid game bot
                KDecide -> pickSmartDecision game bot
                KTrump  -> pickSmartTrump game bot
                _       -> ""
        return (decisionStr, bot)

    notifyStateChange _ _ bot = return bot

----------------------------------------------------------------------------------
-- 2. Heuristics Engine: Rule Selection
----------------------------------------------------------------------------------

pickSmartRule :: KingGame -> SmartBot -> BS.ByteString
pickSmartRule game bot =
    case gameHands game of
        (KingHand (Left rules) _ _ _ : _) ->
            let hand = map parseCard (roundCards game)
                scoredRules = map (\r -> (r, scoreRule r hand bot)) rules
                bestRule = fst $ maximumBy (comparing snd) scoredRules
            in mkPlayStr game "GAME" (Just $ show bestRule)
        _ -> mkPlayStr game "GAME" (Just "POSITIVA")

scoreRule :: KingRule -> [Card] -> SmartBot -> Float
scoreRule rule hand bot = case rule of
    RVaza     -> 50.0 - avgRank hand * 5.0
    RMulheres -> 60.0 - fromIntegral (countRank Queen hand) * 40.0
    RHomens   -> 60.0 - fromIntegral (countRank King hand + countRank Jack hand) * 25.0
    RCopas    -> 60.0 - fromIntegral (countSuit Hearts hand) * 15.0 - avgRank (filterBySuit Hearts hand) * 2.0
    RKing     -> if hasCard (Card King Hearts) hand
                 then if countSuit Hearts hand >= 4 then 20.0 + (riskAversion bot * 20.0) else -50.0
                 else 80.0
    R2Ultimas -> 50.0 - avgRank hand * 3.0 -- Risk of getting stuck with high cards
    RPositiva -> maxSuitStrength hand * 1.5
    _         -> 40.0 -- Default for specific Positivas if they appear

----------------------------------------------------------------------------------
-- 3. Heuristics Engine: Card Play
----------------------------------------------------------------------------------

pickSmartCard :: KingGame -> SmartBot -> BS.ByteString
pickSmartCard game bot =
    let handStr = roundCards game
        hand    = map parseCard handStr
    in case gameHands game of
        [] -> "" -- No active hand state, wait for sync or broadcast
        (currentHand:_) ->
            let rule = case handRule currentHand of
                    Right r -> r
                    _       -> RVaza -- Should not happen
                tableStr = curRound currentHand
                table    = map parseCard tableStr
                validStr = filter (isValidPlay rule tableStr handStr) handStr
                valid    = map parseCard validStr
            in case valid of
                (v:vs) -> 
                    let chosen = chooseCardByRule rule table hand (v:vs) bot game
                    in mkPlayStr game "PLAY" (Just $ unparseCard chosen)
                [] -> case handStr of
                        (fallback:_) -> mkPlayStr game "PLAY" (Just fallback)
                        [] -> "" -- Truly empty hand, skip to avoid loop

chooseCardByRule :: KingRule -> [Card] -> [Card] -> [Card] -> SmartBot -> KingGame -> Card
chooseCardByRule rule table fullHand valid bot game
    | isPositiva rule = playPositive rule table fullHand valid
    | rule == R2Ultimas = play2Ultimas table fullHand valid game
    | otherwise = playNegative rule table fullHand valid bot game

-- | Strategy for Positive Games: Win tricks efficiently
playPositive :: KingRule -> [Card] -> [Card] -> [Card] -> Card
playPositive rule table _ valid =
    case table of
        [] -> case valid of
                (v:vs) -> maximum (v:vs) -- Lead strong
                []     -> Card Ace Spades -- Should not be reachable as valid is non-empty
        (ledCard:_) ->
            let ledSuit = cardSuit ledCard
                trumpSuit = getTrumpSuit rule
                isTrump c = Just (cardSuit c) == trumpSuit
                
                -- Can I win?
                currentWinner = determineWinnerIdx rule ledSuit table
                winningCards = filter (beats rule ledSuit (table !! currentWinner)) valid
            in if null winningCards
               then minimum valid -- Can't win, throw away low
               else minimum winningCards -- Win as cheaply as possible

-- | Strategy for 2ULTIMAS: Win early to shed high cards
play2Ultimas :: [Card] -> [Card] -> [Card] -> KingGame -> Card
play2Ultimas table fullHand valid game =
    let roundNum = 13 - length fullHand + 1
    in if roundNum <= 11
       then maximum valid -- Try to win and keep control early
       else playNegative R2Ultimas table fullHand valid (SmartBot "" 1.0 0.0) game -- Play safe in scoring rounds

-- | Strategy for Negative Games: Avoid winning, target leaders
playNegative :: KingRule -> [Card] -> [Card] -> [Card] -> SmartBot -> KingGame -> Card
playNegative rule table fullHand valid bot game =
    case table of
        [] -> minimum valid -- Lead low
        (ledCard:_) ->
            let ledSuit = cardSuit ledCard
                currentWinnerIdx = determineWinnerIdx rule ledSuit table
                
                -- Safely get winner name
                winnerName = case (gameHands game, players (kingTable game)) of
                    (h:_, plrs) | length plrs == 4 -> plrs !! ((roundTurn h + currentWinnerIdx) `mod` 4)
                    _ -> ""
                
                -- Table Awareness: Are we ganging up?
                targetName = getMatchLeader game
                isTargetWinner = not (null winnerName) && winnerName == targetName && socialLevel bot > 0.5
                
                -- Standard losing strategy: highest card that doesn't win
                losingCards = filter (not . beats rule ledSuit (table !! currentWinnerIdx)) valid
            in if null losingCards
               then if isTargetWinner
                    then maximum valid -- Penalty to leader!
                    else maximum valid -- Forced to win, take it with highest to shed it
               else if isTargetWinner && any (isDanger rule) losingCards
                    then fromMaybe (maximum losingCards) (find (isDanger rule) (sortBy (comparing (invert . rankValue . cardRank)) losingCards))
                    else maximum losingCards

----------------------------------------------------------------------------------
-- 4. Bidding & Auctions
----------------------------------------------------------------------------------

pickSmartBid :: KingGame -> SmartBot -> BS.ByteString
pickSmartBid game bot =
    let hand = map parseCard (roundCards game)
        strength = maxSuitStrength hand
        -- Aggressive bots bid more. 0.3 risk aversion might bid at strength 50, 0.8 at 70.
        threshold = 40.0 + (riskAversion bot * 40.0)
        bid = if strength > threshold
              then floor ((strength - threshold) / 10.0) + 1
              else 0
        finalBid = min bid 5
    in mkPlayStr game "BID" (Just $ show finalBid)

pickSmartDecision :: KingGame -> SmartBot -> BS.ByteString
pickSmartDecision game bot =
    -- For now, simple decision: only accept if we don't have a good hand ourselves
    let hand = map parseCard (roundCards game)
        strength = maxSuitStrength hand
        threshold = 60.0 + (riskAversion bot * 20.0)
    in if strength > threshold
       then mkPlayStr game "DECIDE" (Just "False")
       else mkPlayStr game "DECIDE" (Just "True")

pickSmartTrump :: KingGame -> SmartBot -> BS.ByteString
pickSmartTrump game _ =
    let hand = map parseCard (roundCards game)
        suits = [Clubs, Diamonds, Hearts, Spades]
        bestSuit = maximumBy (comparing (\s -> calculateSuitStrength s hand)) suits
    in mkPlayStr game "TRUMP" (Just $ [suitChar bestSuit])
  where
    suitChar Clubs = 'C'
    suitChar Diamonds = 'D'
    suitChar Hearts = 'H'
    suitChar Spades = 'S'

----------------------------------------------------------------------------------
-- 5. Helper Functions
----------------------------------------------------------------------------------

getMatchLeader :: KingGame -> String
getMatchLeader game =
    let playerNames = players (kingTable game)
        scores = map (\name -> (name, getPlayerScore name game)) playerNames
    in fst $ maximumBy (comparing snd) scores

getPlayerScore :: String -> KingGame -> Int
getPlayerScore name game =
    let table = kingTable game
        pIdx = fromMaybe 0 (name `elemIndex` players table)
    in sum $ concatMap (map (!! pIdx) . handScore) (gameHands game)

countRank :: Rank -> [Card] -> Int
countRank r cards = length $ filter (\c -> cardRank c == r) cards

countSuit :: Suit -> [Card] -> Int
countSuit s cards = length $ filter (\c -> cardSuit c == s) cards

filterBySuit :: Suit -> [Card] -> [Card]
filterBySuit s cards = filter (\c -> cardSuit c == s) cards

avgRank :: [Card] -> Float
avgRank [] = 0
avgRank cards = fromIntegral (sum $ map (rankValue . cardRank) cards) / fromIntegral (length cards)

rankValue :: Rank -> Int
rankValue r = fromEnum r + 2

maxSuitStrength :: [Card] -> Float
maxSuitStrength hand =
    let suits = [Clubs, Diamonds, Hearts, Spades]
    in maximum $ map (`calculateSuitStrength` hand) suits

calculateSuitStrength :: Suit -> [Card] -> Float
calculateSuitStrength s hand =
    let cards = filterBySuit s hand
        len = length cards
        highCards = length $ filter (\c -> cardRank c >= Jack) cards
    in fromIntegral len * 10.0 + fromIntegral highCards * 15.0

hasCard :: Card -> [Card] -> Bool
hasCard c hand = c `elem` hand

determineWinnerIdx :: KingRule -> Suit -> [Card] -> Int
determineWinnerIdx rule ledSuit cards =
    case getTrumpSuit rule of
        Just trump -> if any (\c -> cardSuit c == trump) cards
                      then findMaxIdxBySuit trump cards
                      else findMaxIdxBySuit ledSuit cards
        Nothing    -> findMaxIdxBySuit ledSuit cards

findMaxIdxBySuit :: Suit -> [Card] -> Int
findMaxIdxBySuit s cards =
    let indexed = zip [0..] cards
        suitCards = filter (\(_, c) -> cardSuit c == s) indexed
    in if null suitCards then 0 else fst $ maximumBy (comparing (cardRank . snd)) suitCards

getTrumpSuit :: KingRule -> Maybe Suit
getTrumpSuit RPositivaH = Just Hearts
getTrumpSuit RPositivaS = Just Spades
getTrumpSuit RPositivaD = Just Diamonds
getTrumpSuit RPositivaC = Just Clubs
getTrumpSuit _          = Nothing

beats :: KingRule -> Suit -> Card -> Card -> Bool
beats rule ledSuit winner challenger =
    let trump = getTrumpSuit rule
    in case trump of
        Just t -> if cardSuit challenger == t
                  then cardSuit winner /= t || cardRank challenger > cardRank winner
                  else cardSuit winner /= t && cardSuit challenger == ledSuit && cardRank challenger > cardRank winner
        Nothing -> cardSuit challenger == ledSuit && cardRank challenger > cardRank winner

isDanger :: KingRule -> Card -> Bool
isDanger RMulheres (Card Queen _) = True
isDanger RHomens (Card King _) = True
isDanger RHomens (Card Jack _) = True
isDanger RKing (Card King Hearts) = True
isDanger RCopas (Card _ Hearts) = True
isDanger _ _ = False

invert :: Int -> Int
invert x = -x
