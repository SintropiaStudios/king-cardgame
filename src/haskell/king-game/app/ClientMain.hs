{-# LANGUAGE OverloadedStrings #-}
{- HLINT ignore "Use <$>" -}
module Main where

import Control.Monad (when)

import System.IO ( hPutStrLn, stderr, hSetBuffering, stdout, BufferMode(LineBuffering) )
import System.Exit ( exitFailure )
import System.Environment
import qualified Data.ByteString.Char8 as BS
import Data.List (find)

import KingClient
import BaseClient
import KingAgent
import KingTypes

main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    args <- getArgs
    when (length args < 2) $ do
        hPutStrLn stderr "usage: king-game-client-exe <usrname> <password> [riskAversion] [socialLevel] [tableName]"
        exitFailure
    let usrname = head args
        passwrd = args !! 1
        -- Default values if not provided
        riskVal = if length args >= 3 then read (args !! 2) else 0.5
        socVal  = if length args >= 4 then read (args !! 3) else 0.5
        mTable  = if length args >= 5 then Just (args !! 4) else Nothing
        
        king_srv_addr = "tcp://localhost:5555"
        king_sub_addr = "tcp://localhost:5556"
        
        bot = SmartBot usrname riskVal socVal

    runGameS king_srv_addr king_sub_addr usrname passwrd mTable bot
