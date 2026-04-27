{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module ProductionEnv where

import ServerLogic (MonadGameEnv(..), KingCard)
import System.Random.Shuffle (shuffleM)
import Data.UUID.V4 (nextRandom)
import Data.UUID (toString)

-- A simple wrapper around IO for our production environment
newtype ProductionM a = ProductionM { runProductionM :: IO a }
    deriving (Functor, Applicative, Monad)

instance MonadGameEnv ProductionM where
    generateId = ProductionM $ do
        toString <$> nextRandom

    generateDeck = ProductionM $ do
        let suits = ['H', 'C', 'D', 'S']
            ranks = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
            fullDeck = [r ++ [s] | s <- suits, r <- ranks]

        -- Shuffle the 52 cards
        shuffled <- shuffleM fullDeck

        -- Split into 4 hands of 13 cards each
        let (h1, rest1) = splitAt 13 shuffled
            (h2, rest2) = splitAt 13 rest1
            (h3, h4)    = splitAt 13 rest2
        return [h1, h2, h3, h4]
