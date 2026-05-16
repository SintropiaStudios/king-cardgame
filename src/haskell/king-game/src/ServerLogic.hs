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
import Data.Maybe (fromMaybe, mapMaybe, isJust)
import Control.Monad (when)
import Debug.Trace (trace)

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
-- Internal data
----------------------------------------------------------------------
data ServerUser = ServerUser
    { pName :: String
    , uChannel :: String
    } deriving (Show, Eq)

data GamePhase = Lobby | WaitingForRule | Bidding [(String, Int)] | DecidingBid String | ChoosingTrump String | PlayingTrick [(String, KingCard)] | GameOver
    deriving (Show, Eq)

data ServerTable = ServerTable
    { tName :: String
    , tPlayers :: [ServerUser]
    , tPhase :: GamePhase
    , tActiveTurn :: Int
    , tHandStarter :: Int
    , tPlayedHands :: [(String, KingRule)]
    , tHands :: Map.Map String [KingCard]
    , tHandScores :: [Int]
    , tTotalScores :: [Int]
    } deriving (Show, Eq)

data PollState = NotPolling | Polling [String] | Finished [String]
    deriving (Show, Eq)

data ServerContext = ServerContext
    { scUsers :: Map.Map String ServerUser
    , scTables :: Map.Map String ServerTable
    , scPoll :: PollState
    } deriving (Show, Eq)

availableRulesForPlayer :: [(String, KingRule)] -> String -> [KingRule]
availableRulesForPlayer history playerName =
    let -- 1. Identify which negative rules have been played by ANYONE
        playedNegatives = [ r | (_, r) <- history, not (isPositiva r) ]
        availableNegatives = filter (`notElem` playedNegatives) allNegativeRules

        -- 2. Check if THIS player has already called a Positiva
        hasPlayedPositiva = any (\(p, r) -> p == playerName && isPositiva r) history

        allPositivas = [RPositiva] -- They all "show" as POSITIVA, so just send one

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
            else let newTable = table { tPlayers = currentPlayers ++ [ServerUser name injectedId] }
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
    let tablesWithUser = Map.toList $ Map.filter (\t -> ServerUser usr sec `elem` tPlayers t) (scTables ctx)
    in case tablesWithUser of
        (tId, table):_ -> Just (tId, table)
        [] -> Nothing

-- | Validates ONLY that the user is at the table and using the correct secret.
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
            let bcasts = ["user-list-channel USERLIST " ++ unwords activeUsers]
                ctx' = ctx { scPoll = Finished activeUsers }
            in ("ACK", bcasts, ctx')
        _ -> ("ERROR No active poll", [], ctx)

----------------------------------------------------------------------
-- | The core entry point for all commands.
----------------------------------------------------------------------
handleCommand :: MonadGameEnv m => ServerContext -> [String] -> m (String, [String], ServerContext)
handleCommand ctx tokens = 
    -- trace ("DEBUG: handleCommand tokens=" ++ show tokens) $ 
    handleCommand' ctx tokens

handleCommand' :: MonadGameEnv m => ServerContext -> [String] -> m (String, [String], ServerContext)

----------------------------------------------------------------------
-- AUTHORIZE <username> <password>
----------------------------------------------------------------------
handleCommand' ctx ["AUTHORIZE", usr, _pwd] = do
    channel <- generateId
    let newUser = ServerUser usr channel
        ctx' = ctx { scUsers = Map.insert usr newUser (scUsers ctx) }
    return (channel, [], ctx')

----------------------------------------------------------------------
-- TABLE <username> <channel> [tableName]
----------------------------------------------------------------------
handleCommand' ctx ("TABLE":usr:chan:rest)
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        generatedId <- generateId
        let tId = if null rest then generatedId else head rest
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
handleCommand' ctx ["LIST"] = do
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
handleCommand' ctx ("JOIN":usr:chan:tId:_)
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        secret <- generateId
        case joinTable ctx usr secret tId of
            Left error -> return (error, [], ctx)
            Right (secret, ctx') -> case startTable ctx' tId of
                Nothing               -> return (secret, [], ctx')
                Just (table, ctx'') -> do
                    initialDeck <- generateDeck
                    let handsMap = Map.fromList $ zip (map pName (tPlayers table)) initialDeck
                        updatedT = table { tHands = handsMap }
                        finalCtx = ctx'' { scTables = Map.insert tId updatedT (scTables ctx'') }
                        tablePlayers = getNamesOnTable' table
                        msgTableOrder = tId ++ " START " ++ unwords tablePlayers
                        msgInitialHand = tId ++ " STARTHAND " ++ head tablePlayers ++ " " ++ unwords (map show startingRules)
                    return (secret, [msgTableOrder, msgInitialHand], finalCtx)

----------------------------------------------------------------------
-- GETHAND <username> <secret>
----------------------------------------------------------------------
handleCommand' ctx ["GETHAND", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (_, table, _) ->
            let hand = Map.findWithDefault [] usr (tHands table)
                jsonHand = "[" ++ intercalate ", " (map (\c -> "\"" ++ c ++ "\"") hand) ++ "]"
            in return (jsonHand, [], ctx)

----------------------------------------------------------------------
-- GAME <username> <secret> <rule_string>
----------------------------------------------------------------------
handleCommand' ctx ["GAME", usr, sec, ruleStr] = do
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
                                }
                            ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                        return ("ACK", [tId ++ " BID " ++ nextPlayerName], ctx')
                else do
                    let starterIdx = tHandStarter table
                        starterName = pName (tPlayers table !! starterIdx)
                        updatedTable = table
                            { tPhase = PlayingTrick []
                            , tActiveTurn = starterIdx
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
handleCommand' ctx ["GETTURN", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (_tId, table, _pIndex) -> do
            let turnName = pName (tPlayers table !! tActiveTurn table)
            return (turnName, [], ctx)

----------------------------------------------------------------------
-- PLAY <username> <secret> <card_string>
----------------------------------------------------------------------
handleCommand' ctx ["PLAY", usr, sec, cardStr] = do
    case validateTableMembership ctx usr sec of
        Left err -> return (err, [], ctx)
        Right (tId, table, pIndex) -> do
            case tPhase table of
                PlayingTrick trickCards -> do
                    if tActiveTurn table /= pIndex
                    then return ("ERROR Not your turn", [], ctx)
                    else do
                        let hand = Map.findWithDefault [] usr (tHands table)
                        if cardStr `notElem` hand
                        then return ("ERROR Card not in hand", [], ctx)
                        else do
                            let currentRule = snd $ last (tPlayedHands table)
                                tableCards = map snd trickCards
                            if not (isValidPlay currentRule tableCards hand cardStr)
                            then return ("ERROR Invalid play: must follow suit", [], ctx)
                            else do
                                let newHand = filter (/= cardStr) hand
                                    newHandsMap = Map.insert usr newHand (tHands table)
                                    newTrickCards = trickCards ++ [(usr, cardStr)]
                                    isTrickOver = length newTrickCards == 4
                                if not isTrickOver
                                then do
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
                                    let playedCards = map snd newTrickCards
                                        roundNum = 13 - length newHand
                                        (winRelIdx, score) = evaluateTrick currentRule roundNum playedCards
                                        winnerName = fst (newTrickCards !! winRelIdx)
                                        winnerIdx = fromMaybe 0 (winnerName `elemIndex` map pName (tPlayers table))
                                        updatedScores = addScore winnerIdx score (tHandScores table)
                                        endRoundBcast = tId ++ " ENDROUND " ++ winnerName ++ " " ++ show score
                                        updatedTable = table
                                            { tPhase = PlayingTrick []
                                            , tActiveTurn = winnerIdx
                                            , tHands = newHandsMap
                                            , tHandScores = updatedScores
                                            }
                                        ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                        bcast = [ tId ++ " PLAY " ++ cardStr
                                                , endRoundBcast
                                                , tId ++ " TURN " ++ winnerName
                                                ]
                                        remainingPool = concat (Map.elems newHandsMap)
                                        handEnded = isHandComplete currentRule remainingPool
                                    if not handEnded
                                    then return ("ACK", bcast, ctx')
                                    else do
                                        let newTotalScores = zipWith (+) (tTotalScores table) updatedScores
                                            endHandBCast  = tId ++ " ENDHAND " ++ unwords (map show updatedScores)
                                            isGameOver = length (tPlayedHands table) == 10
                                        if isGameOver
                                            then do
                                                let endGameBCast = tId ++ " GAMEOVER " ++ unwords (map show newTotalScores)
                                                    updatedTableG = table
                                                        { tPhase = GameOver
                                                        , tHandScores = updatedScores
                                                        , tTotalScores = newTotalScores
                                                        , tHands = Map.empty
                                                        }
                                                    ctx'' = ctx' { scTables = Map.insert tId updatedTableG (scTables ctx') }
                                                    bcasts = [ tId ++ " PLAY " ++ cardStr
                                                            , endRoundBcast
                                                            , endHandBCast
                                                            , endGameBCast
                                                            ]
                                                return ("ACK", bcasts, ctx'')
                                            else do
                                                newDeck <- generateDeck
                                                let nextStarterIdx = (tHandStarter updatedTable + 1) `mod` 4
                                                    nextStarterName = pName (tPlayers updatedTable !! nextStarterIdx)
                                                    finalTable = updatedTable
                                                        { tPhase = WaitingForRule
                                                        , tHandStarter = nextStarterIdx
                                                        , tActiveTurn = nextStarterIdx
                                                        , tHandScores = [0, 0, 0, 0]
                                                        , tTotalScores = newTotalScores
                                                        , tHands = Map.fromList $ zip (map pName (tPlayers updatedTable)) newDeck
                                                        }
                                                    availableRules = availableRulesForPlayer (tPlayedHands finalTable) nextStarterName
                                                    msgStartHand = tId ++ " STARTHAND " ++ nextStarterName ++ " " ++ unwords (map show availableRules)
                                                    ctx'' = ctx' { scTables = Map.insert tId finalTable (scTables ctx') }
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
handleCommand' ctx ["BID", usr, sec, valStr] = do
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
                            hasPassed name = case lookup name (reverse newLog) of
                                               Just 0  -> True
                                               _       -> False
                            activePlayers = filter (not . hasPassed) (map pName (tPlayers table))
                            activeOthers = filter (/= callerName) activePlayers
                        let highestBids = filter (\(_, v) -> v > 0) newLog
                            (highestBidder, maxBid) = if null highestBids
                                                      then ("", 0)
                                                      else foldl1 (\acc x -> if snd x > snd acc then x else acc) highestBids
                        let getNextActive currentIdx =
                                let nextIdx = (currentIdx + 1) `mod` 4
                                    nextName = pName (tPlayers table !! nextIdx)
                                in (if (nextName == callerName) || hasPassed nextName then getNextActive nextIdx else (nextIdx, nextName))
                            (nextIdx, nextName) = getNextActive pIndex
                        let isAuctionOver = null activeOthers || (not (null highestBids) && nextName == highestBidder)
                        if isAuctionOver
                        then do
                            let finalWinner = if null highestBids then callerName else highestBidder
                                updatedTable = table { tPhase = DecidingBid finalWinner }
                                ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                bcasts = [ tId ++ " BIDS " ++ valStr, tId ++ " DECIDE " ++ callerName ]
                            return ("ACK", bcasts, ctx')
                        else do
                            let updatedTable = table { tPhase = Bidding newLog, tActiveTurn = nextIdx }
                                ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                                bcasts = [ tId ++ " BIDS " ++ valStr, tId ++ " BID " ++ nextName ]
                            return ("ACK", bcasts, ctx')
                _ -> return ("ERROR Game is not in bidding phase", [], ctx)

----------------------------------------------------------------------
-- DECIDE <username> <secret> <True/False>
----------------------------------------------------------------------
handleCommand' ctx ["DECIDE", usr, sec, decisionStr] = do
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
handleCommand' ctx ["TRUMP", usr, sec, suitStr] = do
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
                                , tPlayedHands = tPlayedHands table ++ [(usr, readRule ("POSITIVA" ++ suitStr))]
                                }
                            ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                            bcasts = [ tId ++ " GAME POSITIVA " ++ suitStr, tId ++ " TURN " ++ starterName ]
                        return ("ACK", bcasts, ctx')
                _ -> return ("ERROR Game is not waiting for trump selection", [], ctx)

----------------------------------------------------------------------
-- LEAVE <username> <secret>
----------------------------------------------------------------------
handleCommand' ctx ["LEAVE", usr, sec] = do
    case validateTableMembership ctx usr sec of
        Left err -> return ("ERROR Player not in table", [], ctx)
        Right (tId, table, _pIndex) -> do
            let isNotStarted = tPhase table == Lobby
                leaveBcast = tId ++ " LEAVE " ++ usr
            if isNotStarted
            then do
                let newPlayers = filter (\p -> pName p /= usr) (tPlayers table)
                    updatedTable = table { tPlayers = newPlayers }
                    ctx' = ctx { scTables = Map.insert tId updatedTable (scTables ctx) }
                return ("ACK", [leaveBcast], ctx')
            else do
                let scoreStr = unwords (map show (tTotalScores table))
                    gameOverBcast = tId ++ " GAMEOVER " ++ scoreStr
                    ctx' = ctx { scTables = Map.delete tId (scTables ctx) }
                return ("ACK", [leaveBcast, gameOverBcast], ctx')

----------------------------------------------------------------------
-- LISTUSERS (No arguments)
----------------------------------------------------------------------
handleCommand' ctx ["LISTUSERS"] = do
    case scPoll ctx of
        Polling _ -> return ("ERROR Listing in progress", [], ctx)
        _ -> do
            let allUsers = Map.elems (scUsers ctx)
                bcasts = map (\u -> uChannel u ++ " CONFIRM_AVAILABLE") allUsers
                ctx' = ctx { scPoll = Polling [] }
            return ("ACK", bcasts, ctx')

----------------------------------------------------------------------
-- AVAILABLE <username> <channel>
----------------------------------------------------------------------
handleCommand' ctx ["AVAILABLE", usr, chan]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        case scPoll ctx of
            Polling activeUsers -> do
                let ctx' = if usr `elem` activeUsers then ctx else ctx { scPoll = Polling (usr : activeUsers) }
                return ("ACK", [], ctx')
            _ -> return ("ERROR Timeout on response", [], ctx)

----------------------------------------------------------------------
-- MATCH <username> <channel> <p2> <p3> <p4>
----------------------------------------------------------------------
handleCommand' ctx ["MATCH", usr, chan, p2, p3, p4]
    | not (isAuthorized ctx usr chan) = pure ("ERROR User not authorized", [], ctx)
    | otherwise = do
        case scPoll ctx of
            Finished activeUsers -> do
                let requestedOthers = [p2, p3, p4]
                if all (`elem` activeUsers) requestedOthers
                then do
                    tId <- generateId
                    let newTable = ServerTable
                            { tName = tId, tPlayers = [ServerUser usr chan], tPhase = Lobby, tActiveTurn = 0, tHandStarter = 0
                            , tPlayedHands = [], tHands = Map.empty, tHandScores = [0, 0, 0, 0], tTotalScores = [0, 0, 0, 0] }
                        ctx' = ctx { scTables = Map.insert tId newTable (scTables ctx) }
                        otherUsers = mapMaybe (`Map.lookup` scUsers ctx') requestedOthers
                        bcasts = map (\srvUsr -> uChannel srvUsr ++ " ASKJOIN " ++ tId) otherUsers
                    return (tId, bcasts, ctx')
                else
                    return ("ERROR You must inform 3 or 4 other valid players", [], ctx)
            _ -> return ("ERROR No recent active user list", [], ctx)

----------------------------------------------------------------------
-- FALLBACK
----------------------------------------------------------------------
handleCommand' ctx _ = pure ("ERROR Invalid or unrecognized command", [], ctx)
