{-# LANGUAGE OverloadedStrings #-}
{- HLINT ignore "Use <$>" -}
module Main where

import Control.Monad (when)

import System.IO ( hPutStrLn, stderr )
import System.Exit ( exitFailure )
import System.Environment
import qualified Data.ByteString.Char8 as BS
import Data.List (find)

import KingClient
import BaseClient
import KingTypes
import GameRules (isValidPlay)

----------------------------------------------------------------------------------
-- A Concrete Agent Implementation (Replacing KingBotAgent)
----------------------------------------------------------------------------------
newtype SimpleBot = SimpleBot { sName :: String }

instance ContextAwareAgent SimpleBot where
    decideAction action game state = do
        let decisionStr = case action of
                KTrump  -> mkPlayStr game "TRUMP" (Just "H")
                KBid    -> mkPlayStr game "BID" (Just "0")
                KDecide -> mkPlayStr game "DECIDE" (Just "False")
                KRule   -> pickRule game
                KPlay   -> pickCard game
                _       -> ""
        return (decisionStr, state)

    -- Bots don't care about passive updates right now
    notifyStateChange _ _ = return

-- Helper to safely pick the first available valid card using the new GameRules
pickCard :: KingGame -> BS.ByteString
pickCard game =
    let hand  = roundCards game
        hands = gameHands game
    in case hands of
        (KingHand (Right rule) table _ _ : _) ->
            case find (isValidPlay rule table hand) hand of
                Just validCard -> mkPlayStr game "PLAY" (Just validCard)
                Nothing        -> mkPlayStr game "PLAY" (Just $ head hand) -- Fallback
        _ -> mkPlayStr game "PLAY" (Just $ head hand)

-- Helper to pick the first available rule
pickRule :: KingGame -> BS.ByteString
pickRule game =
    case gameHands game of
        (KingHand (Left (r:_)) _ _ _ : _) -> mkPlayStr game "GAME" (Just $ show r)
        _ -> mkPlayStr game "GAME" (Just "POSITIVA")


main :: IO ()
main = do
    args <- getArgs
    when (length args /= 2) $ do
        hPutStrLn stderr "usage: king-game-client-exe <usrname> <password>"
        exitFailure
    let usrname = head args
        passwrd = args !! 1
        king_srv_addr = "tcp://localhost:5555"
        king_sub_addr = "tcp://localhost:5556"

    runGameS king_srv_addr king_sub_addr usrname passwrd (SimpleBot usrname)
