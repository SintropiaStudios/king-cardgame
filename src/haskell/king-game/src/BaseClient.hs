{- HLINT ignore "Use <$>" -}
module BaseClient
    ( ClientEnv(..)
    , ContextAwareAgent(..)
    , runAgentThread
    , networkLoop
    , runGameS
    )
 where

import Control.Monad.State ( StateT(runStateT), MonadIO(liftIO) )

import Control.Monad (when)
import Control.Concurrent.STM
    ( TVar, atomically, newTVar, readTVar, readTVarIO, writeTVar,
      newEmptyTMVar, putTMVar, takeTMVar, TMVar,
      TQueue, newTQueue, readTQueue, writeTQueue, orElse )
import Control.Concurrent.Async (concurrently_)
import System.IO ()
import System.Exit ()
import System.Environment ()
import qualified Data.ByteString.Char8 as BS
import System.ZMQ4.Monadic
    ( ZMQ, Sender, Receiver, Socket,
      connect, runZMQ, socket,
      Req(Req), Sub(Sub) )

import KingClient (KingGame, Player(..), ExpectedAction(..), ActionResponse(..), executeActionS, mkGame, startGame, updateGame)

----------------------------------------------------------------------------------
-- 1. The STM Communication Bridge
----------------------------------------------------------------------------------
data ClientEnv = ClientEnv
    { envGameState   :: TVar KingGame
    , envActionReq   :: TMVar ExpectedAction
    , envActionRsp   :: TMVar BS.ByteString
    , envNotify      :: TQueue String
    }

----------------------------------------------------------------------------------
-- 2. The Extensible Agent Typeclass
----------------------------------------------------------------------------------
class ContextAwareAgent a where
    -- | Called when the server expects an action (KPlay, KRule, etc.)
    -- Returns the formulated ZMQ command and the updated internal agent state.
    decideAction :: ExpectedAction -> KingGame -> a -> IO (BS.ByteString, a)
    -- | Passive notification hook
    -- Called whenever server broadcasts messages
    notifyStateChange :: String -> KingGame -> a -> IO a

----------------------------------------------------------------------------------
-- 3. The Thread Runners
----------------------------------------------------------------------------------

-- | The Agent Thread: Blocks until the network asks for a decision, then thinks.
runAgentThread :: ContextAwareAgent a => ClientEnv -> a -> IO ()
runAgentThread env = loop
  where
    loop agentState = do
        -- Wait for EITHER an active request OR a passive notification
        task <- atomically $
            (Left <$> takeTMVar (envActionReq env))
            `orElse`
            (Right <$> readTQueue (envNotify env))

        game <- readTVarIO (envGameState env)

        case task of
            Left action -> do
                (decisionStr, newAgentState) <- decideAction action game agentState
                atomically $ putTMVar (envActionRsp env) decisionStr
                loop newAgentState
            Right msgStr -> do
                newAgentState <- notifyStateChange msgStr game agentState
                loop newAgentState

-- | The Network Thread: Handles all ZMQ traffic and state updates.
networkLoop :: (Sender s, Receiver s, Receiver r) => Socket z r -> Socket z s -> ClientEnv -> KingGame -> ZMQ z ()
networkLoop info srv env game = do
    ((action, msgStr), game') <- runStateT (updateGame srv info 10) game

    -- Sync objective game state to the bridge
    liftIO $ atomically $ writeTVar (envGameState env) game'

    -- If a real broadcast happened, queue it for the Agent thread!
    liftIO $ when (msgStr /= "") $ atomically $ writeTQueue (envNotify env) msgStr

    case action of
        KOver msg -> liftIO $ putStrLn $ "Game has ended: " ++ msg
        KWait     -> networkLoop info srv env game'
        _         -> do
            -- A helper loop to relentlessly demand a valid action
            let requestAction loopAction = do                
                    -- Request a decision from the Agent thread
                    liftIO $ atomically $ putTMVar (envActionReq env) loopAction
                    -- Wait for the Agent to reply
                    decisionStr <- liftIO $ atomically $ takeTMVar (envActionRsp env)
                    -- Capture the server's response to our action
                    reply <- executeActionS srv decisionStr                    
                    -- If the server rejects the play, ask the UI again!
                    case reply of
                        KError replyStr -> do
                            liftIO $ putStrLn $ "[Haskell] Server rejected play: " ++ replyStr
                            requestAction loopAction
                        KAck -> return ()
            
            requestAction action
            networkLoop info srv env game'

runGameS :: ContextAwareAgent a => String -> String -> String -> String -> a -> IO ()
runGameS srv_addr sub_addr usrname passwrd initialAgent = do
    -- Initialize the STM Bridge
    env <- atomically $ do
        gState <- newTVar (mkGame (Player usrname "") "" "")
        req    <- newEmptyTMVar
        rsp    <- newEmptyTMVar
        notif  <- newTQueue
        return $ ClientEnv gState req rsp notif

    -- Run both threads simultaneously
    concurrently_
        (runAgentThread env initialAgent)
        (runZMQ $ do
            srv <- socket Req
            connect srv srv_addr

            info <- socket Sub
            connect info sub_addr

            (suc, g) <- runStateT (startGame srv info usrname passwrd) (mkGame (Player usrname "") "" "")
            if not suc
                then liftIO $ putStrLn "Error during game setup."
                else networkLoop info srv env g
        )
