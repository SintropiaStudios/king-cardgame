{-# LANGUAGE FlexibleContexts #-}

module ServerLogic
    ( ServerContext
    , GamePhase(..)
    , ServerTable(..)
    , MonadGameEnv(..)
    , KingCard
    , emptyServerContext
    , handleCommand
    , finishList
    ) where

import qualified Data.Map.Strict as Map
import Data.List (intercalate, find, elemIndex)
import Data.Maybe (fromMaybe, mapMaybe)
import Control.Monad (when)

import KingTypes (KingRule(..), KingCard, readRule, isPositiva, allNegativeRules, startingRules)
import GameRules (evaluateTrick, isValidPlay, isHandComplete)
import KingClient (KingGame(secret))

----------------------------------------------------------------------
-- The Typeclass (Environment Interface)
----------------------------------------------------------------------
class Monad m => MonadGameEnv m where
    generateId   :: m String         -- For Auth channels, Table IDs, Secrets
    generateDeck :: m [[KingCard]]   -- Always returns 4 lists of 13 cards

----------------------------------------------------------------------
-- The Data Types
----------------------------------------------------------------------

-- | Defines the exact state of the table
data GamePhase
    = Lobby                             -- < 4 players
    | WaitingForRule                    -- Waiting for the hand starter to pick a game
    | Bidding [(String, Int)]           -- Positiva Auction: Log of all bids (Name, Amount)
    | DecidingBid String                -- HighestBidderName
    | ChoosingTrump String              -- WinnerName
    | PlayingTrick [(String, KingCard)] -- Cards played in the current trick
    | GameOver
    deriving (Show, Eq)

-- | Represents the `User` class in Python
data ServerUser = ServerUser
    { uName    :: String
    , uChannel :: String
    } deriving (Show, Eq)

data ServerPlayer = ServerPlayer
    { pName   :: String
    , pSecret :: String
    } deriving (Show, Eq)

-- | Represents the `KingTable` class in Python
data ServerTable = ServerTable
    { tName           :: String
    , tPlayers        :: [ServerPlayer]
    , tPhase          :: GamePhase
    , tActiveTurn     :: Int                           -- Index (0-3) of whose turn it is
    , tHandStarter    :: Int                           -- Index (0-3) of who starts the hand
    , tPlayedHands    :: [(String, KingRule)]          -- History of played hands (only rules for now)
    , tHands          :: Map.Map String [KingCard]     -- The Dealt Cards
    , tHandScores     :: [Int]                         -- Tracks current points [P0, P1, P2, P3]
    , tTotalScores    :: [Int]                         -- Tracls Total accumulated points
    } deriving (Show, Eq)

-- Polling State (For Listing users)
data PollingState = NotPolling | Polling [String] | Finished [String]
    deriving (Show, Eq)

-- | Replaces global dicts g_users, g_tables, g_players
data ServerContext = ServerContext
    { scUsers  :: Map.Map String ServerUser     -- Tracks authorized users
    , scTables :: Map.Map String ServerTable    -- Tracks available tables
    , scPoll   :: PollingState                  -- Tracks the LISTUSERS roll call
    } deriving (Show, Eq)

-- | Calculates the available rules for a specific player based on the table's history log
availableRulesForPlayer :: [(String, KingRule)] -> String -> [KingRule]
availableRulesForPlayer history playerName =
    let -- 1. Identify which negative rules have been played by ANYONE
        playedNegatives = [ r | (_, r) <- history, not (isPositiva r) ]
        availableNegatives = filter (`notElem` playedNegatives) allNegativeRules

        -- 2. Check if THIS player has already called a Positiva
        hasPlayedPositiva = any (\(p, r) -> p == playerName && isPositiva r) history

        allPositivas = [RPositiva] -- They all "show" as POSITIVA, so just send one [RPositivaH, RPositivaC, RPositivaS, RPositivaD]

    in if hasPlayedPositiva
       then if null availableNegatives
            then allPositivas     -- Forced to pick Positiva because no negatives are left
            else availableNegatives -- Must pick an available negative, Positiva is locked
       else availableNegatives ++ allPositivas -- Can pick anything

-- | General helper for Either pipelines
maybeToEither :: e -> Maybe a -> Either e a
maybeToEither err = maybe (Left err) Right

emptyServerContext :: ServerContext
emptyServerContext = ServerContext Map.empty Map.empty NotPolling

-- | Checks if a user is authorized based on their name and channel.
isAuthorized :: ServerContext -> String -> String -> Bool
isAuthorized ctx name channel =
    case Map.lookup name (scUsers ctx) of
        Just user -> uChannel user == channel
        Nothing   -> False

-- | Retrieves a Table given its ID
getTable :: ServerContext -> String -> Maybe ServerTable
getTable ctx tId = Map.lookup tId (scTables ctx)

-- | Given an Authorized User, attempt to join a table by its ID and Either Errors or Returns secret and new Server Context
joinTable :: ServerContext -> String -> String -> String -> Either String (String, ServerContext)
joinTable ctx name injectedId tId = do
    table <- maybeToEither "ERROR Table does not exist" (getTable ctx tId)
    let currentPlayers = tPlayers table
        alreadyInTable = name `elem` map pName currentPlayers
    if alreadyInTable
        then Left "ERROR User already in table"
        else if length currentPlayers >= 4
            then Left "ERROR Table is already full"
            else let newTable = table { tPlayers = currentPlayers ++ [ServerPlayer name injectedId] }
                     ctx' = ctx { scTables = Map.insert tId newTable (scTables ctx) }
                 in Right (injectedId, ctx')

-- | Attempts to start a Table given its ID
startTable :: ServerContext -> String -> Maybe (ServerTable, ServerContext)
startTable ctx tId = do
    table <- getTable ctx tId
    if length (tPlayers table) == 4
        then
            let pNames = map pName (tPlayers table)
                updatedTable = table { tPhase = WaitingForRule }
                ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
            in Just (updatedTable, ctx')
        else Nothing

-- | Retrieves a list of the Player's Names on the table, in the order they are sit.
getNamesOnTable :: ServerContext -> String -> [String]
getNamesOnTable ctx tId = maybe [] (map pName . tPlayers) (getTable ctx tId)

getNamesOnTable' :: ServerTable -> [String]
getNamesOnTable' = map pName . tPlayers

-- | Finds the table and player info for a given user
findUserTable :: ServerContext -> String -> String -> Maybe (String, ServerTable)
findUserTable ctx usr sec =
    let tablesWithUser = Map.toList $ Map.filter (\t -> ServerPlayer usr sec `elem` tPlayers t) (scTables ctx)
    in case tablesWithUser of
        (tId, table):_ -> Just (tId, table)
        [] -> Nothing

-- | Validates ONLY that the user is at the table and using the correct secret.
-- Turn validation is left to the specific commands.
validateTableMembership :: ServerContext -> String -> String -> Either String (String, ServerTable, Int)
validateTableMembership ctx usr sec = do
    (tId, table) <- maybeToEither "ERROR User not at table" (findUserTable ctx usr sec)
    let pIndex = fromMaybe 0 (usr `elemIndex` map pName (tPlayers table))
    Right (tId, table, pIndex)

-- | Helper to add score to an index of the given array
addScore :: Int -> Int -> [Int] -> [Int]
addScore targetIdx points = zipWith (\idx currentScore -> if idx == targetIdx then currentScore + points else currentScore) [0..3]

----------------------------------------------------------------------
-- FINISHLIST (Internal command to inform LISTUSER timer ended)
----------------------------------------------------------------------
finishList :: ServerContext -> (String, [String], ServerContext)
finishList ctx =
    case scPoll ctx of
        Polling activeUsers ->
            let bcasts = ["user-list-channel " ++ unwords activeUsers]
                ctx' = ctx { scPoll = Finished activeUsers }
            in ("ACK", bcasts, ctx')
        _ -> ("ERROR No active poll", [], ctx)

----------------------------------------------------------------------
-- | The core pure state machine.
-- Takes: Context -> InjectedID -> CommandWords
-- Returns: (DirectReply, OptionalBroadcast, NewContext)
----------------------------------------------------------------------
handleCommand :: MonadGameEnv m => ServerContext -> [String] -> m (String, [String], ServerContext)

----------------------------------------------------------------------
-- AUTHORIZE <username> <password>
----------------------------------------------------------------------
-- Note: In final system, password check against a DB here.
-- For this pure state, we trust the auth and generate the user.
handleCommand ctx ["AUTHORIZE", usr, _pwd] = do
    channel <- generateId
    let newUser = ServerUser usr channel
        ctx' = ctx { scUsers = Map.insert usr newUser (scUsers ctx) }
    return (channel, [], ctx')

----------------------------------------------------------------------
-- TABLE <username> <channel>
----------------------------------------------------------------------
handleCommand ctx ["TABLE", usr, chan]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        tId <- generateId
        -- Python's server.py creates the table but does NOT automatically add the user to it.
        let newTable = ServerTable
                    { tName = tId
                    , tPlayers = []
                    , tPhase = Lobby
                    , tActiveTurn = 0
                    , tHandStarter = 0
                    , tPlayedHands = []
                    , tHands = Map.empty
                    , tHandScores = [0, 0, 0, 0]
                    , tTotalScores = [0, 0, 0, 0]
                    }
            ctx' = ctx { scTables = Map.insert tId newTable (scTables ctx) }
        return (tId, [], ctx')

----------------------------------------------------------------------
-- LIST (No arguments)
----------------------------------------------------------------------
handleCommand ctx ["LIST"] = do
    let tablesList = Map.toList (scTables ctx)

        formatTable (tId, table) =
            "{\"name\": \"" ++ tId ++ "\", \"players\": [" ++
            intercalate ", " (map (\p -> "\"" ++ pName p ++ "\"") (tPlayers table)) ++
            "]}"

        jsonStr = "[" ++ intercalate ", " (map formatTable tablesList) ++ "]"

    return (jsonStr, [], ctx)

----------------------------------------------------------------------
-- JOIN <username> <channel> <table_id>
----------------------------------------------------------------------
handleCommand ctx ["JOIN", usr, chan, tId]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        secret <- generateId
        case joinTable ctx usr secret tId of
            Left error -> return (error, [], ctx)
            -- Join is good, now attempt to start the table if we have 4 players
            Right (secret, ctx') -> case startTable ctx' tId of
                Nothing               -> return (secret, [], ctx') -- Not enough, but the join was successful
                Just (table, ctx'') -> do
                    initialDeck <- generateDeck
                    let handsMap = Map.fromList $ zip (map pName (tPlayers table)) initialDeck
                        updatedT = table { tHands = handsMap }
                        finalCtx = ctx'' { scTables = Map.insert tId updatedT (scTables ctx'') }
                        tablePlayers = getNamesOnTable' table   -- TODO needs to be shuffled so that the hand starter is first in the list (turn has to be set as well to match)
                        msgTableOrder = tId ++ " START " ++ unwords tablePlayers
                        msgInitialHand = tId ++ " STARTHAND " ++ head tablePlayers ++ " " ++ unwords (map show startingRules)

                    return (secret, [msgTableOrder, msgInitialHand], finalCtx)

----------------------------------------------------------------------
-- GETHAND <username> <secret>
----------------------------------------------------------------------
handleCommand ctx ["GETHAND", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (_, table, _) ->
            let hand = Map.findWithDefault [] usr (tHands table)
                -- Converts ["2H", "3C"] to valid JSON string '["2H", "3C"]'
                jsonHand = "[" ++ intercalate ", " (map (\c -> "\"" ++ c ++ "\"") hand) ++ "]"
            in return (jsonHand, [], ctx)

----------------------------------------------------------------------
-- GAME <username> <secret> <rule_string>
----------------------------------------------------------------------
handleCommand ctx ["GAME", usr, sec, ruleStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, pIndex) ->
            if tPhase table /= WaitingForRule
            then return ("ERROR Game is not waiting for a rule", [], ctx)
            else if tActiveTurn table /= pIndex
            then return ("ERROR Not your turn to choose a rule", [], ctx)
            else
                let rule = readRule ruleStr
                    allowedRules = availableRulesForPlayer (tPlayedHands table) usr
                in if rule `notElem` allowedRules
                then return ("ERROR Rule not available for this player at this time", [], ctx)
                else if isPositiva rule
                    then do
                        let nextTurn = (pIndex + 1) `mod` 4
                            nextPlayerName = pName (tPlayers table !! nextTurn)
                            updatedTable = table
                                { tPhase = Bidding []
                                , tActiveTurn = nextTurn
                                -- Don't add to Op-Log as Trump hasn't been decided
                                }
                            ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }

                        -- Emit EXACTLY what Python did
                        return ("ACK", [tId ++ " BID " ++ nextPlayerName], ctx')

                -- IF IT IS A NEGATIVE RULE: Go straight to the first trick!
                else do
                    let starterIdx = tHandStarter table
                        starterName = pName (tPlayers table !! starterIdx)
                        updatedTable = table
                            { tPhase = PlayingTrick []
                            , tActiveTurn = starterIdx
                            -- Add to Op-Log
                            , tPlayedHands = tPlayedHands table ++ [(usr, rule)]
                            }
                        ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }

                        bcasts = [ tId ++ " GAME " ++ ruleStr
                                 , tId ++ " TURN " ++ starterName
                                 ]
                    return ("ACK", bcasts, ctx')

----------------------------------------------------------------------
-- GETTURN <username> <secret>
----------------------------------------------------------------------
handleCommand ctx ["GETTURN", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (_tId, table, _pIndex) -> do
            -- tActiveTurn is the index (0-3) of the player on the clock
            let turnName = pName (tPlayers table !! tActiveTurn table)
            return (turnName, [], ctx)

----------------------------------------------------------------------
-- PLAY <username> <secret> <card_string>
----------------------------------------------------------------------
handleCommand ctx ["PLAY", usr, sec, cardStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, pIndex) -> do
            case tPhase table of
                PlayingTrick trickCards -> do
                    -- 1. Turn Validation
                    if tActiveTurn table /= pIndex
                    then return ("ERROR Not your turn", [], ctx)
                    else do
                        -- 2. Hand Validation (Do they actually have the card?)
                        let hand = Map.findWithDefault [] usr (tHands table)
                        if cardStr `notElem` hand
                        then return ("ERROR Card not in hand", [], ctx)
                        else do
                            -- 3. GameRules Validation (Must follow suit, etc.)
                            -- The active rule is the last one appended to the op-log
                            let currentRule = snd $ last (tPlayedHands table)
                                tableCards = map snd trickCards

                            if not (isValidPlay currentRule tableCards hand cardStr)
                            then return ("ERROR Invalid play: must follow suit", [], ctx)
                            else do
                                -- 4. State Update (Remove card from hand, add to table)
                                let newHand = filter (/= cardStr) hand
                                    newHandsMap = Map.insert usr newHand (tHands table)
                                    newTrickCards = trickCards ++ [(usr, cardStr)]

                                    isTrickOver = length newTrickCards == 4

                                if not isTrickOver
                                then do
                                    -- Trick continues, just advance the turn
                                    let nextTurn = (tActiveTurn table + 1) `mod` 4
                                        updatedTable = table
                                            { tPhase = PlayingTrick newTrickCards
                                            , tActiveTurn = nextTurn
                                            , tHands = newHandsMap
                                            }
                                        ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                        bcast = [ tId ++ " PLAY " ++ cardStr
                                                , tId ++ " TURN " ++ getNamesOnTable' updatedTable !! nextTurn
                                                ]
                                    return ("ACK", bcast, ctx')
                                else do
                                    -- 5. Trick Evaluation (4 cards played)
                                    let playedCards = map snd newTrickCards
                                        -- Calculate the round number (1-13) based on cards remaining
                                        roundNum = 14 - length newHand

                                        (winRelIdx, score) = evaluateTrick currentRule roundNum playedCards
                                        winnerName = fst (newTrickCards !! winRelIdx)
                                        winnerIdx = fromMaybe 0 (winnerName `elemIndex` map pName (tPlayers table))
                                        -- Add the trick's score to the winner's tally
                                        updatedScores = addScore winnerIdx score (tHandScores table)
                                        endRoundBcast = tId ++ " ENDROUND " ++ winnerName ++ " " ++ show score

                                        updatedTable = table
                                            { tPhase = PlayingTrick [] -- Clear the trick for the next round
                                            , tActiveTurn = winnerIdx  -- Winner leads the next trick
                                            , tHands = newHandsMap
                                            , tHandScores = updatedScores
                                            }
                                        ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }

                                        bcast = [ tId ++ " PLAY " ++ cardStr
                                                , endRoundBcast
                                                , tId ++ " TURN " ++ winnerName
                                                ]
                                        -- Calculate the global remaining pool and check if hand ends
                                        remainingPool = concat (Map.elems newHandsMap)
                                        handEnded = isHandComplete currentRule remainingPool

                                    if not handEnded
                                    then return ("ACK", bcast, ctx') -- Returns ENDROUND sequence only
                                    else do
                                        let newTotalScores = zipWith (+) (tTotalScores table) updatedScores
                                            endHandBCast  = tId ++ " ENDHAND " ++ unwords (map show updatedScores)
                                            isGameOver = length (tPlayedHands table) == 10 -- Game Finishes after 10 hands

                                        if isGameOver
                                            then do
                                                -- 10 hands complete. Calculate the global winner!
                                                let maxScore = maximum newTotalScores
                                                    winnerGlobalIdx = fromMaybe 0 (maxScore `elemIndex` newTotalScores)
                                                    globalWinnerName = pName (tPlayers table !! winnerGlobalIdx)
                                                    endGameBCast = tId ++ " GAMEOVER " ++ unwords (map show newTotalScores)

                                                    updatedTable = table
                                                        { tPhase = GameOver
                                                        , tHandScores = updatedScores
                                                        , tTotalScores = newTotalScores
                                                        , tHands = Map.empty -- Empty the table
                                                        }
                                                    ctx'' = ctx' { scTables = Map.insert tId updatedTable (scTables ctx') }

                                                    bcasts = [ tId ++ " PLAY " ++ cardStr
                                                            , endRoundBcast
                                                            , endHandBCast
                                                            , endGameBCast
                                                            ]
                                                return ("ACK", bcasts, ctx'')
                                            else do
                                                newDeck <- generateDeck
                                                let nextStarterIdx = (tHandStarter updatedTable + 1) `mod` 4
                                                    nextStarterName = getNamesOnTable' finalTable !! nextStarterIdx
                                                    availableRules = availableRulesForPlayer (tPlayedHands finalTable) nextStarterName
                                                    msgStartHand = tId ++ " STARTHAND " ++ nextStarterName ++ " " ++ unwords (map show availableRules)

                                                    finalTable = updatedTable
                                                        { tPhase = WaitingForRule
                                                        , tHandStarter = nextStarterIdx
                                                        , tActiveTurn = nextStarterIdx
                                                        , tHandScores = [0, 0, 0, 0]
                                                        , tTotalScores = newTotalScores
                                                        , tHands = Map.fromList $ zip (map pName (tPlayers table)) newDeck
                                                        }
                                                    ctx'' = ctx' { scTables = Map.insert tId finalTable (scTables ctx') }

                                                    -- Prepare STARTHAND message for the next hand
                                                    bcast'= [ tId ++ " PLAY " ++ cardStr
                                                            , endRoundBcast
                                                            , endHandBCast
                                                            , msgStartHand
                                                            ]
                                                return ("ACK", bcast', ctx'')

                _ -> return ("ERROR Game is not in trick-playing phase", [], ctx)

----------------------------------------------------------------------
-- BID <username> <secret> <amount>
----------------------------------------------------------------------
handleCommand ctx ["BID", usr, sec, valStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, pIndex) -> do
            case tPhase table of
                Bidding bidLog -> do
                    let callerName = pName (tPlayers table !! tHandStarter table)
                    if tActiveTurn table /= pIndex
                    then return ("ERROR Not your turn", [], ctx)
                    else do
                        let bidVal = read valStr :: Int
                            newLog = bidLog ++ [(usr, bidVal)]

                            -- A player is "active" if they haven't bid 0.
                            -- (If they haven't bid at all yet, they are implicitly active)
                            hasPassed name = case lookup name (reverse newLog) of
                                               Just 0  -> True
                                               _       -> False

                            activePlayers = filter (not . hasPassed) (map pName (tPlayers table))
                            activeOthers = filter (/= callerName) activePlayers

                        -- Determine the highest bidder so far
                        let highestBids = filter (\(_, v) -> v > 0) newLog
                            (highestBidder, maxBid) = if null highestBids
                                                      then ("", 0)
                                                      else foldl1 (\acc x -> if snd x > snd acc then x else acc) highestBids

                        -- Calculate who is logically next
                        let getNextActive currentIdx =
                                let nextIdx = (currentIdx + 1) `mod` 4
                                    nextName = pName (tPlayers table !! nextIdx)
                                in (if (nextName == callerName) || hasPassed nextName then getNextActive nextIdx else (nextIdx, nextName))

                            (nextIdx, nextName) = getNextActive pIndex

                        -- Check auction termination conditions
                        let isAuctionOver = null activeOthers || (not (null highestBids) && nextName == highestBidder)

                        if isAuctionOver
                        then do
                            let finalWinner = if null highestBids then callerName else highestBidder
                                updatedTable = table
                                    { tPhase = DecidingBid finalWinner
                                    }
                                ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                bcasts = [ tId ++ " BIDS " ++ valStr
                                         , tId ++ " DECIDE " ++ callerName
                                         ]
                            return ("ACK", bcasts, ctx')
                        else do
                            let updatedTable = table
                                    { tPhase = Bidding newLog
                                    , tActiveTurn = nextIdx
                                    }
                                ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                bcasts = [ tId ++ " BIDS " ++ valStr
                                         , tId ++ " BID " ++ nextName
                                         ]
                            return ("ACK", bcasts, ctx')
                _ -> return ("ERROR Game is not in bidding phase", [], ctx)

----------------------------------------------------------------------
-- DECIDE <username> <secret> <True/False>
----------------------------------------------------------------------
handleCommand ctx ["DECIDE", usr, sec, decisionStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, _pIndex) -> do
            case tPhase table of
                DecidingBid highestBidder -> do
                    let callerName = pName (tPlayers table !! tHandStarter table)
                    if usr /= callerName
                    then return ("ERROR Only the caller can decide", [], ctx)
                    else do
                        let accepted = decisionStr == "True"
                            trumpChooser = if accepted then highestBidder else callerName

                            updatedTable = table { tPhase = ChoosingTrump trumpChooser }
                            ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                            bcasts = [ tId ++ " CHOOSETRUMP " ++ trumpChooser ]

                        return ("ACK", bcasts, ctx')
                _ -> return ("ERROR Game is not waiting for a decision", [], ctx)

----------------------------------------------------------------------
-- TRUMP <username> <secret> <suit_char>
----------------------------------------------------------------------
handleCommand ctx ["TRUMP", usr, sec, suitStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, _pIndex) -> do
            case tPhase table of
                ChoosingTrump trumpChooser -> do
                    if usr /= trumpChooser
                    then return ("ERROR Not your turn to choose trump", [], ctx)
                    else do
                        let starterIdx = tHandStarter table
                            starterName = pName (tPlayers table !! starterIdx)

                            updatedTable = table
                                { tPhase = PlayingTrick []
                                , tActiveTurn = starterIdx
                                -- Add to Op-Log with chosen trump now so the rule is consumed
                                , tPlayedHands = tPlayedHands table ++ [(usr, readRule ("POSITIVA" ++ suitStr))]
                                }
                            ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }

                            -- Emit exactly what Python did: GAME POSITIVA <suit>
                            bcasts = [ tId ++ " GAME POSITIVA " ++ suitStr
                                     , tId ++ " TURN " ++ starterName
                                     ]

                        return ("ACK", bcasts, ctx')
                _ -> return ("ERROR Game is not waiting for trump selection", [], ctx)

----------------------------------------------------------------------
-- LEAVE <username> <secret>
----------------------------------------------------------------------
handleCommand ctx ["LEAVE", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return ("ERROR Player not in table", [], ctx)
        Right (tId, table, _pIndex) -> do
            let isNotStarted = tPhase table == Lobby
                leaveBcast = tId ++ " LEAVE " ++ usr

            if isNotStarted
            then do
                -- Safely remove the player from the lobby
                let newPlayers = filter (\p -> pName p /= usr) (tPlayers table)
                    updatedTable = table { tPlayers = newPlayers }
                    ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                return ("ACK", [leaveBcast], ctx')
            else do
                -- Game was already running! Destroy the table and boot everyone.
                let scoreStr = unwords (map show (tTotalScores table))
                    bcasts = [ leaveBcast
                             , tId ++ " GAMEOVER " ++ scoreStr
                             ]
                    -- Remove the table entirely from the server context
                    ctx' = ctx { scTables = Map.delete tId (scTables ctx) }
                return ("ACK", bcasts, ctx')

----------------------------------------------------------------------
-- LISTUSERS (No arguments)
----------------------------------------------------------------------
handleCommand ctx ["LISTUSERS"] = do
    case scPoll ctx of
        Polling _ -> return ("ERROR Listing in progress", [], ctx)
        _ -> do
            -- Broadcast CONFIRM_AVAILABLE to every connected user's private channel
            let allUsers = Map.elems (scUsers ctx)
                bcasts = map ((++ " CONFIRM_AVAILABLE") . uChannel) allUsers
                ctx' = ctx { scPoll = Polling [] }
            return ("ACK", bcasts, ctx')

----------------------------------------------------------------------
-- AVAILABLE <username> <channel>
----------------------------------------------------------------------
handleCommand ctx ["AVAILABLE", usr, chan]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        case scPoll ctx of
            Polling activeUsers -> do
                -- Add the user to the active list if they aren't already there
                let newActive = if usr `elem` activeUsers then activeUsers else activeUsers ++ [usr]
                    ctx' = ctx { scPoll = Polling newActive }
                return ("ACK", [], ctx')
            _ -> return ("ERROR Timeout on response", [], ctx)

----------------------------------------------------------------------
-- MATCH <username> <channel> <p2> <p3> <p4>
----------------------------------------------------------------------
handleCommand ctx ["MATCH", usr, chan, p2, p3, p4]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        case scPoll ctx of
            Finished activeUsers -> do
                let requestedOthers = [p2, p3, p4]
                    validOthers = filter (`elem` activeUsers) requestedOthers

                if length validOthers == 3
                then do
                    -- All requested players are available. Generate a new table ID!
                    tId <- generateId

                    -- Create an empty Lobby. (The creator still needs to send JOIN!)
                    let newTable = ServerTable
                            { tName = tId
                            , tPlayers = []
                            , tPhase = Lobby
                            , tActiveTurn = 0
                            , tHandStarter = 0
                            , tPlayedHands = []
                            , tHands = Map.empty
                            , tHandScores = [0, 0, 0, 0]
                            , tTotalScores = [0, 0, 0, 0]
                            }
                        ctx' = ctx { scTables = Map.insert tId newTable (scTables ctx) }

                        -- Retrieve the private channels for the 3 invited players
                        otherUsers = mapMaybe (`Map.lookup` scUsers ctx') validOthers
                        bcasts = map (\srvUsr -> uChannel srvUsr ++ " ASKJOIN " ++ tId) otherUsers

                    return (tId, bcasts, ctx')
                else
                    return ("ERROR You must inform 3 or 4 other valid players", [], ctx)
            _ -> return ("ERROR No recent active user list", [], ctx)

----------------------------------------------------------------------
-- FALLBACK
----------------------------------------------------------------------
handleCommand ctx _ = pure ("ERROR Invalid or unrecognized command", [], ctx)
