{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified System.ZMQ4.Monadic as Z
import Control.Concurrent (forkIO, threadDelay, writeChan)
import Control.Concurrent.MVar (newMVar, modifyMVar)
import Control.Concurrent.Chan (newChan, readChan, writeChan)
import Control.Monad (forever, forM_, when, void)
import Control.Monad.IO.Class (liftIO, MonadIO (liftIO))
import Data.ByteString.Char8 (pack, unpack)

import ServerLogic (emptyServerContext, handleCommand, finishList)
import ProductionEnv (runProductionM)

main :: IO ()
main = do
    putStrLn "Starting King Server (Haskell Edition)..."
    
    -- Initialize the global thread-safe state
    stateMVar <- newMVar emptyServerContext
    -- Thread-safe queue for outbound broadcasts
    bcastChan <- newChan
    
    -- Fork the dedicated ZMQ Publisher Thread
    forkIO $ Z.runZMQ $ do
        statusPublisher <- Z.socket Z.Pub
        Z.bind statusPublisher "tcp://127.0.0.1:5556"
        forever $ do
            msg <- liftIO $ readChan bcastChan
            liftIO $ putStrLn $ "Broadcasting: " ++ msg
            Z.send statusPublisher [] (pack msg)

    -- Run the Main ZMQ Action (REP) Thread
    Z.runZMQ $ do        
        actionServer <- Z.socket Z.Rep
        Z.bind actionServer "tcp://127.0.0.1:5555"        
        liftIO $ putStrLn "ZMQ Sockets Bound. Listening for commands..."
        
        -- The Main Game Loop
        forever $ do
            -- Wait for a command from a client
            msgByteString <- Z.receive actionServer
            let cmdString = unpack msgByteString
                cmdTokens = words cmdString
                
            liftIO $ putStrLn $ "Received: " ++ cmdString
            
            -- Lock the state, run the pure logic, and update the state
            (reply, bcasts) <- liftIO $ modifyMVar stateMVar $ \ctx -> do                
                -- Execute your pure logic inside the Production IO environment
                (repStr, bcastStrs, newCtx) <- runProductionM (handleCommand ctx cmdTokens)                
                -- modifyMVar expects (new_state, return_value)
                return (newCtx, (repStr, bcastStrs))
                
            -- Broadcast all resulting state changes to all subscribers
            liftIO $ forM_ bcasts (writeChan bcastChan)
                
            -- Reply ACK or ERROR reply back to the requester
            Z.send actionServer [] (pack reply)
            
            -- The Matchmaking Timer Intercept
            -- If this was a successful LISTUSERS command, fork the 10-second timer
            when (not (null cmdTokens) && head cmdTokens == "LISTUSERS" && reply == "ACK") $
                void $ liftIO $ forkIO $ do
                    -- Wait 10 seconds (10,000,000 microseconds)
                    threadDelay 10000000 
                    
                    -- Lock the state again and apply our internal pure function
                    timerBcasts <- modifyMVar stateMVar $ \ctx -> do
                        let (_, bcastStrs, newCtx) = finishList ctx
                        return (newCtx, bcastStrs)
                    
                    -- Queue the resulting list broadcast
                    forM_ timerBcasts (writeChan bcastChan)
