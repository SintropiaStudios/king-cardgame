{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Main where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forever, forM_, void)
import Data.Aeson (FromJSON, decode)
import qualified Data.ByteString.Lazy as BL
import GHC.Generics (Generic)
import System.Environment (getEnv, lookupEnv)
import System.IO (hSetBuffering, stdout, BufferMode(LineBuffering))
import Data.Maybe (fromMaybe)

import BaseClient
import qualified KingClient as KC
import KingAgent
import System.ZMQ4.Monadic (runZMQ, socket, connect, Req(..), Sub(..), subscribe, liftIO)

data BotConfig = BotConfig
    { name :: String
    , risk :: Float
    , social :: Float
    } deriving (Show, Generic)

instance FromJSON BotConfig

-- | The worker instance that actually plays a game
runWorker :: String -> String -> String -> String -> BotConfig -> Int -> IO ()
runWorker srv sub usr pwd config iid = do
    let instanceName = name config ++ "_i" ++ show iid
        bot = SmartBot instanceName (risk config) (social config)
    putStrLn $ "[Worker] Starting " ++ instanceName
    -- We use Nothing as the table ID because runGameS is called after the ID is already known
    -- Actually, runGameS expects the table ID in mTable. 
    runGameS srv sub instanceName instanceName (Just usr) bot -- usr here is the tId passed from idleLoop

main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    putStrLn "Starting King Bot Pool Server..."

    srvAddr <- fromMaybe "tcp://127.0.0.1:5555" <$> lookupEnv "KING_SERVER_ADDR"
    subAddr <- fromMaybe "tcp://127.0.0.1:5556" <$> lookupEnv "KING_SUB_ADDR"
    poolPath <- fromMaybe "scripts/bot_pool.json" <$> lookupEnv "BOT_POOL_PATH"

    poolData <- BL.readFile poolPath
    let bots = fromMaybe [] (decode poolData :: Maybe [BotConfig])
    putStrLn $ "Loaded " ++ show (length bots) ++ " bot configurations."

    -- For each bot, start a manager thread that idles and forks workers
    forM_ (zip [1..] bots) $ \(idx, config) -> forkIO $ runZMQ $ do
        srv <- socket Req
        connect srv srvAddr
        info <- socket Sub
        connect info subAddr
        
        -- Authorize as the "base" bot name
        p <- KC.authorize srv info (name config) (name config)
        liftIO $ putStrLn $ "[Manager] " ++ name config ++ " is online and idling."
        
        let managerLoop instanceCounter = do
                -- Wait for an invitation
                tId <- idleLoop info srv p
                -- Fork a worker to handle the table
                liftIO $ void $ forkIO $ runWorker srvAddr subAddr tId (name config) config instanceCounter
                -- Continue listening for more invites
                managerLoop (instanceCounter + 1)
        
        managerLoop 1

    -- Keep the main thread alive
    forever $ threadDelay 1000000
