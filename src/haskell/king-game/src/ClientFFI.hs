{-# LANGUAGE ForeignFunctionInterface #-}
module ClientFFI where

import Foreign.C.String (CString, newCString, peekCString, withCString)
import Foreign.Ptr
import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import qualified Data.ByteString.Char8 as BS
import System.IO.Unsafe (unsafePerformIO)
import Control.Monad (void)

import BaseClient
import KingClient

----------------------------------------------------------------------------------
-- Global STM Bridge State (Required because C++ function calls lack Haskell context)
----------------------------------------------------------------------------------
globalResponse :: TMVar BS.ByteString
globalResponse = unsafePerformIO newEmptyTMVarIO
{-# NOINLINE globalResponse #-}

globalGameState :: TVar (Maybe KingGame)
globalGameState = unsafePerformIO (newTVarIO Nothing)
{-# NOINLINE globalGameState #-}

----------------------------------------------------------------------------------
-- The C++ Agent Instance
----------------------------------------------------------------------------------
newtype CppAgent = CppAgent (FunPtr (CString -> IO ()))

-- Dynamic wrapper to allow Haskell to invoke the provided C++ function pointer
foreign import ccall safe "dynamic"
    invokeCb :: FunPtr (CString -> IO ()) -> CString -> IO ()

instance ContextAwareAgent CppAgent where
    decideAction action game agent@(CppAgent cb) = do
        -- Sync the latest game state into the global TVar for C++ to query
        atomically $ writeTVar globalGameState (Just game)

        -- Alert C++ that an action is required
        withCString (show action) $ \c_action ->
            invokeCb cb c_action

        -- Get the raw decision from C++ (e.g., "PLAY 2H" or "GAME POSITIVA H")
        rawRsp <- waitForResponse

        -- Parse it into Command and Arguments
        let rawString = BS.unpack rawRsp
            parts     = words rawString
            cmd       = if null parts then "" else head parts
            args      = if length parts > 1 then Just (unwords (tail parts)) else Nothing

            -- Pipe it through mkPlayStr
            finalStr  = mkPlayStr game cmd args

        return (finalStr, agent)

    -- | Passive Updates
    notifyStateChange msgStr game agent@(CppAgent cb) = do
        atomically $ writeTVar globalGameState (Just game)

        -- Prefix with KUpdate so C++ knows how to parse it
        withCString ("KUpdate " ++ msgStr) $ \c_action ->
            invokeCb cb c_action

        return agent

-- | Helper function to safely wait for C++ without triggering BlockedIndefinitelyOnSTM
waitForResponse :: IO BS.ByteString
waitForResponse = do
    mRsp <- atomically $ tryTakeTMVar globalResponse
    case mRsp of
        Just rsp -> return rsp
        Nothing  -> do
            threadDelay 5000 -- Sleep for 5ms, then check again
            waitForResponse

----------------------------------------------------------------------------------
-- C-API Exports
----------------------------------------------------------------------------------

-- | Boot up the client thread. C++ calls this once.
foreign export ccall "start_client" startClientFFI
    :: CString -> CString -> CString -> CString -> FunPtr (CString -> IO ()) -> IO ()

startClientFFI :: CString -> CString -> CString -> CString -> FunPtr (CString -> IO ()) -> IO ()
startClientFFI c_srv c_sub c_usr c_pass cb = do
    srv  <- peekCString c_srv
    sub  <- peekCString c_sub
    usr  <- peekCString c_usr
    pass <- peekCString c_pass

    -- C++ manages this thread but it is now blocked under Haskell control
    runGameS srv sub usr pass (CppAgent cb)

-- | C++ calls this to provide a decision (e.g., "PLAY Alice sec-A 10H")
foreign export ccall "submit_action" submitActionFFI :: CString -> IO ()

submitActionFFI :: CString -> IO ()
submitActionFFI c_action = do
    action <- peekCString c_action
    -- Use tryPutTMVar so C++ doesn't accidentally deadlock itself if it double-clicks
    void $ atomically $ tryPutTMVar globalResponse (BS.pack action)

-- | Let C++ fetch the current hand
foreign export ccall "get_player_hand" getPlayerHandFFI :: IO CString

getPlayerHandFFI :: IO CString
getPlayerHandFFI = do
    mGame <- readTVarIO globalGameState
    case mGame of
        Nothing -> newCString ""
        Just g  -> do
            -- roundCards holds the player's current hand. 
            -- We join the cards into a single space-separated string (e.g., "2H 10S KD")
            let handStr = unwords (roundCards g)
            newCString handStr -- Allocates memory that C++ MUST free!

-- | Let C++ fetch the available rules for the current hand
foreign export ccall "get_available_rules" getAvailableRulesFFI :: IO CString

getAvailableRulesFFI :: IO CString
getAvailableRulesFFI = do
    mGame <- readTVarIO globalGameState
    case mGame of
        Nothing -> newCString ""
        Just g  -> do
            case gameHands g of
                -- Match the active hand and extract the Left (available) rules
                (KingHand (Left rules) _ _ _ : _) -> do
                    let rulesStr = unwords (map show rules)
                    newCString rulesStr
                _ -> newCString "" -- Return empty if a rule is already chosen

-- | Let C++ fetch the cards currently played on the table
foreign export ccall "get_table_cards" getTableCardsFFI :: IO CString

getTableCardsFFI :: IO CString
getTableCardsFFI = do
    mGame <- readTVarIO globalGameState
    case mGame of
        Nothing -> newCString ""
        Just g  -> case gameHands g of
            (h:_) -> newCString (unwords $ curRound h)
            _     -> newCString "" -- No hand started yet

-- | Example State Getter: Let C++ poll the current active turn
foreign export ccall "get_active_turn" getActiveTurnFFI :: IO Int

getActiveTurnFFI :: IO Int
getActiveTurnFFI = do
    mGame <- readTVarIO globalGameState
    case mGame of
        Nothing -> return (-1)
        Just g  -> return (activeTurn g)
