{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE BlockArguments #-}
{- HLINT ignore "Use tuple-section" -}

import Test.Hspec

import KingTypes
import GameRules

import ServerLogic
import KingClient

import Control.Monad.State
import Data.Maybe (fromJust)
import qualified Data.Map as Map

-- 1. Create our Test Monad
type TestEnvState = ([String], [[[KingCard]]])  -- (Generated IDs, Generated Decks)
newtype TestEnv a = TestEnv { runTestEnv :: State TestEnvState a }
    deriving (Functor, Applicative, Monad, MonadState TestEnvState)

-- 2. Define how our Test Monad satisfies the interface
instance MonadGameEnv TestEnv where
    generateId = do
        (ids, decks) <- get
        case ids of
            (nextId:rest) -> do
                put (rest, decks)
                return nextId
            [] -> error "No IDs available"

    generateDeck :: TestEnv [[KingCard]]
    generateDeck = do
        (ids, decks) <- get
        case decks of
            (nextDeck:rest) -> do
                put (ids, rest)
                return nextDeck
            [] -> error "No decks available"

-- 3. Helpers to easily run commands in our test suite
runCmd'' :: ServerContext -> [String] -> [String] -> [[[KingCard]]] -> (String, [String], ServerContext)
runCmd'' ctx cmd ids decks = evalState (runTestEnv (handleCommand ctx cmd)) (ids, decks)

runCmd' :: ServerContext -> [String] -> [String] -> (String, [String], ServerContext)
runCmd' ctx cmd ids = runCmd'' ctx cmd ids []

runCmd :: ServerContext -> [String] -> (String, [String], ServerContext)
runCmd ctx cmd = runCmd' ctx cmd []

-- 4. Our setup function is now breathtakingly clean
setupStartedGame :: [[[KingCard]]] -> (ServerContext, String)
setupStartedGame decks =
    let c0 = emptyServerContext
        (_, _, cA)  = runCmd' c0 ["AUTHORIZE", "Alice", "pass"] ["chan-A"]
        (_, _, cT1) = runCmd' cA ["TABLE", "Alice", "chan-A"] ["table-1"]
        (_, _, cJ1) = runCmd' cT1 ["JOIN", "Alice", "chan-A", "table-1"] ["sec-A"]

        (_, _, cB)  = runCmd' cJ1 ["AUTHORIZE", "Bob", "pass"] ["chan-B"]
        (_, _, cJ2) = runCmd' cB ["JOIN", "Bob", "chan-B", "table-1"] ["sec-B"]

        (_, _, cC)  = runCmd' cJ2 ["AUTHORIZE", "Cat", "pass"] ["chan-C"]
        (_, _, cJ3) = runCmd' cC ["JOIN", "Cat", "chan-C", "table-1"] ["sec-C"]

        (_, _, cD)  = runCmd' cJ3 ["AUTHORIZE", "Dave", "pass"] ["chan-D"]
        (_, _, cJ4) = runCmd'' cD ["JOIN", "Dave", "chan-D", "table-1"] ["sec-D"] decks
    in (cJ4, "table-1")

-- This helper function runs the command and CRASHES if it fails
runStep context cmd envDecks = 
    let (reply, _, newCtx) = runCmd'' context cmd [] envDecks
    in if reply == "ACK" 
        then newCtx
        else error $ "\n\n!!! STATE MACHINE BROKE !!!\n" 
                    ++ "Attempted Command: " ++ unwords cmd ++ "\n"
                    ++ "Server Rejected With: " ++ reply ++ "\n\n"

playAuction :: ServerContext -> [(String, String, c)] -> Int -> ServerContext
playAuction ctx players starterIdx =
    let (p0Name, p0Sec, p0Card) = players !! (starterIdx `mod` 4)
        (p1Name, p1Sec, p1Card) = players !! ((starterIdx + 1) `mod` 4)
        (p2Name, p2Sec, p2Card) = players !! ((starterIdx + 2) `mod` 4)
        (p3Name, p3Sec, p3Card) = players !! ((starterIdx + 3) `mod` 4)

        -- Define the sequence of commands and their environment payloads
        auctionSteps = [ (["BID", p1Name, p1Sec, "0"], [])
                       , (["BID", p2Name, p2Sec, "0"], [])
                       , (["BID", p3Name, p3Sec, "0"], [])
                       , (["DECIDE", p0Name, p0Sec, "False"], [])
                       , (["TRUMP", p0Name, p0Sec, ""], [])
                       ]
                       
    -- Fold over the list, feeding the resulting state of each step into the next
    in foldl (\currentCtx (cmd, env) -> runStep currentCtx cmd env) ctx auctionSteps

-- We add `nextDeck` as an argument
playMicroHand :: ServerContext -> [(String, String, KingCard)] -> Int -> [Char] -> [[KingCard]] -> ServerContext
playMicroHand ctx players starterIdx ruleStr nextDeck =
    let (p0Name, p0Sec, p0Card) = players !! (starterIdx `mod` 4)
        (p1Name, p1Sec, p1Card) = players !! ((starterIdx + 1) `mod` 4)
        (p2Name, p2Sec, p2Card) = players !! ((starterIdx + 2) `mod` 4)
        (p3Name, p3Sec, p3Card) = players !! ((starterIdx + 3) `mod` 4)

        -- 1. Apply the GAME command
        ctxAfterGame = runStep ctx ["GAME", p0Name, p0Sec, ruleStr] []
        
        -- 2. Conditionally fold the Auction steps if POSITIVA
        ctxBeforePlay = if ruleStr == "POSITIVA" 
                        then playAuction ctxAfterGame players starterIdx 
                        else ctxAfterGame

        -- 3. Define the PLAY commands
        playSteps = [ (["PLAY", p0Name, p0Sec, p0Card], [])
                    , (["PLAY", p1Name, p1Sec, p1Card], [])
                    , (["PLAY", p2Name, p2Sec, p2Card], [])
                    , (["PLAY", p3Name, p3Sec, p3Card], [nextDeck])
                    ]
                    
    -- Fold the PLAY commands over the prepared state
    in foldl (\currentCtx (cmd, env) -> runStep currentCtx cmd env) ctxBeforePlay playSteps

main :: IO ()
main = hspec $ do
    ----------------------------------------------------------------------
    -- 1. GAME RULES & CONSTRAINTS
    ----------------------------------------------------------------------
    describe "GameRules.isValidPlay" $ do
        -- Base Game Constraints
        describe "Base Game Constraints (Following Suit)" $ do
            it "allows playing anything on an empty table" $ do
                -- assert BaseGame().hand_constraint([], ['2C', '3H'], '3H')
                isValidPlay RVaza [] ["2C", "3H"] "3H" `shouldBe` True

            it "forces player to follow the table's led suit" $ do
                -- assert BaseGame().hand_constraint(['2C'], ['2H', '3C'], '3C')
                isValidPlay RVaza ["2C"] ["2H", "3C"] "3C" `shouldBe` True

            it "prevents playing a different suit if the player has the led suit" $ do
                -- assert not BaseGame().hand_constraint(['2C'], ['2H', '3C'], '2H')
                isValidPlay RVaza ["2C"] ["2H", "3C"] "2H" `shouldBe` False

            it "allows discarding if the player is void in the led suit" $ do
                -- assert BaseGame().hand_constraint(['AD', 'JD', 'QH'], ['2C', '3C'], '2C')
                isValidPlay RVaza ["AD", "JD", "QH"] ["2C", "3C"] "2C" `shouldBe` True

        -- Rule-Specific Constraints
        -- Copas (No Hearts)
        describe "Copas (No Hearts) Constraints" $ do
            it "allows starting with a non-heart" $ do
                -- assert Copas().hand_constraint([], ['2C', '3H'], '2C')
                isValidPlay RCopas [] ["2C", "3H"] "2C" `shouldBe` True

            it "prevents starting with a heart if other suits are available" $ do
                -- assert not Copas().hand_constraint([], ['2C', '3H'], '3H')
                isValidPlay RCopas [] ["2C", "3H"] "3H" `shouldBe` False
        -- King (No King of Hearts)
        describe "King (No King of Hearts) Constraints" $ do
            it "forces the player to discard the King of Hearts when void in led suit" $ do
                -- assert King().hand_constraint(['2C'], ['2H', 'KH', '3D'], 'KH')
                isValidPlay RKing ["2C"] ["2H", "KH", "3D"] "KH" `shouldBe` True
                isValidPlay RKing ["2C"] ["2H", "KH", "3D"] "2H" `shouldBe` False

        -- Other rules have no additional constraints beyond the base game
        describe "Constraints for Vaza, Mulheres, Homens, 2Ultimas, and Positiva" $ do
            it "rely entirely on the general trick-taking constraints" $ do
                -- Mulheres: Must follow suit
                isValidPlay RMulheres ["2C"] ["2H", "3C"] "3C" `shouldBe` True
                -- Homens: Cannot break suit if holding it
                isValidPlay RHomens ["2C"] ["2H", "3C"] "2H" `shouldBe` False
                -- 2Ultimas: Can discard if void
                isValidPlay R2Ultimas ["2C"] ["2H", "3H"] "3H" `shouldBe` True
                -- Positiva: No special play constraints, just follows suit
                isValidPlay RPositiva ["2C"] ["2H", "3C"] "3C" `shouldBe` True
                isValidPlay RPositivaH ["2C"] ["2H", "3C"] "3C" `shouldBe` True
    ----------------------------------------------------------------------
    -- 2. TRICK EVALUATION, SCORING & HAND EXHAUSTION
    ----------------------------------------------------------------------
    describe "GameRules.evaluateTrick" $ do
        -- Base Game Logic
        describe "Trick Winner Logic (Base Game)" $ do
            it "awards the trick to the highest card of the led suit" $ do
                -- assert Vaza().play_round(['2H', '5H', 'AS', '4H']) == (1, -25) 
                -- Note: Python test says -25, but class Vaza says score = -20. We will use -20.
                evaluateTrick RVaza 1 ["2H", "5H", "AS", "4H"] `shouldBe` (1, -20)

            it "ignores higher cards of non-led suits (no trumps)" $ do
                -- assert Vaza().play_round(['TD', '5C', 'AS', '4H']) == (0, -25)
                evaluateTrick RVaza 1 ["TD", "5C", "AS", "4H"] `shouldBe` (0, -20)
        
        describe "Scoring Rules" $ do
            it "Mulheres (No Queens) scores -50 for each Queen" $ do
                -- assert Mulheres().play_round(['5H', 'QS', 'JS', '2H']) == (0, -50)
                evaluateTrick RMulheres 1 ["5H", "QS", "JS", "2H"] `shouldBe` (0, -50)
                -- assert Mulheres().play_round(['QD', 'QS', 'QC', 'QH']) == (0, -200)
                evaluateTrick RMulheres 1 ["QD", "QS", "QC", "QH"] `shouldBe` (0, -200)

            it "Homens (No Kings or Jacks) scores -30 for each King or Jack" $ do
                -- assert Homens().play_round(['TC', 'KS', 'JC', '5H']) == (2, -60)
                evaluateTrick RHomens 1 ["TC", "KS", "JC", "5H"] `shouldBe` (2, -60)

            it "Copas (No Hearts) scores -20 for each Heart" $ do
                -- assert Copas().play_round(['5H', 'TH', 'AD', '2H']) == (1, -60)
                evaluateTrick RCopas 1 ["5H", "TH", "AD", "2H"] `shouldBe` (1, -60)

            it "King (No King of Hearts) scores -160 if the King of Hearts is present" $ do
                -- assert King().play_round(['AH', '6C', 'KH', 'TH']) == (0, -160)
                evaluateTrick RKing 1 ["AH", "6C", "KH", "TH"] `shouldBe` (0, -160)
                evaluateTrick RKing 1 ["5H", "AS", "AC", "TH"] `shouldBe` (3, 0)

            it "DuasUltimas scores 0 for rounds 1-11, and -90 for rounds 12 and 13" $ do
                -- Python checks for round > 10 (0-indexed) so rounds 11 and 12. 
                -- In 1-indexed, that's rounds 12 and 13.
                evaluateTrick R2Ultimas 10 ["5H", "KS", "AC", "TH"] `shouldBe` (3, 0)
                evaluateTrick R2Ultimas 12 ["5H", "QS", "JS", "2H"] `shouldBe` (0, -90)
                evaluateTrick R2Ultimas 13 ["5D", "QD", "JS", "2H"] `shouldBe` (1, -90)

        describe "Positiva & Trumps" $ do
            it "scores +25 per trick and awards the trick to the highest trump if played" $ do
                -- assert Positiva('H').play_round(['5D', '6H', 'AD', 'TD']) == (1, 25)
                evaluateTrick RPositivaH 1 ["5D", "6H", "AD", "TD"] `shouldBe` (1, 25)

            it "awards the trick to the highest led suit if no trump is played" $ do
                -- assert Positiva('H').play_round(['5C', '2S', 'AC', 'TC']) == (2, 25)
                evaluateTrick RPositivaH 1 ["5C", "2S", "AC", "TC"] `shouldBe` (2, 25)

            it "awards the trick to the highest led suit if Positiva has no trump" $ do
                -- assert Positiva('').play_round(['5C', '2H', 'AD', 'TS']) == (0, 25)
                evaluateTrick RPositiva 1 ["5C", "2H", "AD", "TS"] `shouldBe` (0, 25)

        describe "GameRules: Hand Exhaustion (isHandComplete)" $ do      
            it "ends RKing immediately when the King of Hearts is missing from remaining cards" $ do
                -- KH is still in someone's hand
                isHandComplete RKing ["2H", "KH", "3C"] `shouldBe` False 
                -- KH has been played
                isHandComplete RKing ["2H", "3C", "4D"] `shouldBe` True

            it "ends RMulheres only when all 4 Queens have been played" $ do
                isHandComplete RMulheres ["QH", "2C", "3D"] `shouldBe` False
                isHandComplete RMulheres ["QC", "QS"] `shouldBe` False
                -- No Queens left in the remaining card pool
                isHandComplete RMulheres ["2H", "3C", "4D", "JD"] `shouldBe` True

            it "ends RHomens only when all 4 Jacks and 4 Kings have been played" $ do
                isHandComplete RHomens ["JH", "2C"] `shouldBe` False
                isHandComplete RHomens ["KC", "4D"] `shouldBe` False
                isHandComplete RHomens ["QH", "3C", "10D"] `shouldBe` True

            it "ends RCopas only when all 13 Hearts have been played" $ do
                isHandComplete RCopas ["2H", "3C"] `shouldBe` False
                -- No cards ending in 'H' remain
                isHandComplete RCopas ["3C", "4D", "5S"] `shouldBe` True

            it "forces RVaza, R2Ultimas, and RPositiva to play until the 13th trick" $ do
                -- Even if only one card is left, these games must finish
                isHandComplete RVaza ["2C"] `shouldBe` False
                isHandComplete R2Ultimas ["3D"] `shouldBe` False
                isHandComplete RPositiva ["4S"] `shouldBe` False
                
                -- Only True when the remaining pool is completely empty
                isHandComplete RVaza [] `shouldBe` True
    ----------------------------------------------------------------------
    -- 3. CLIENT SERIALIZATION
    ----------------------------------------------------------------------
    describe "KingClient Serialization" $ do
        it "correctly parses wire strings into KingRules" $ do
            readRule "VAZA" `shouldBe` RVaza
            readRule "2ULTIMAS" `shouldBe` R2Ultimas
            readRule "POSITIVAH" `shouldBe` RPositivaH

        it "safely falls back to RPositiva for unknown rules" $ do
            readRule "INVALID_JUNK" `shouldBe` RPositiva

        it "correctly formats KingRules back into wire strings" $ do
            show RVaza `shouldBe` "VAZA"
            show RKing `shouldBe` "KING"
    ----------------------------------------------------------------------
    -- 4. CLIENT STATE TRANSITIONS
    ----------------------------------------------------------------------
    describe "KingClient State Transitions" $ do
        let dummyPlayer = Player "Alice" "channel-123"
            initGame = mkGame dummyPlayer "Table1" "secret-456"

        it "initializes the game state correctly" $ do
            user (player initGame) `shouldBe` "Alice"
            name (kingTable initGame) `shouldBe` "Table1"

        it "adds players to the table" $ do
            let gameWithPlayers = setPlayers initGame ["Alice", "Bob", "Charlie", "Dave"]
            players (kingTable gameWithPlayers) `shouldBe` ["Alice", "Bob", "Charlie", "Dave"]

        it "starts a hand and sets the active turn" $ do
            let gameWithPlayers = setPlayers initGame ["Alice", "Bob", "Charlie", "Dave"]
                -- "Bob" is the starter. Bob is at index 1.
                gameHandStarted = startHand gameWithPlayers "Bob" [RVaza, RCopas]

            activeTurn gameHandStarted `shouldBe` 1
            length (gameHands gameHandStarted) `shouldBe` 1

        it "removes a card from the player's hand when they play it" $ do
            let gameWithPlayers = setPlayers initGame ["Alice", "Bob", "Charlie", "Dave"]
                gameHandStarted = startHand gameWithPlayers "Alice" [RVaza]
                gameWithCards   = setupCards gameHandStarted ["2H", "3C", "AH"]

                -- Alice plays the 3 of Clubs
                gameAfterPlay   = playCard gameWithCards "3C"

            -- The card should be removed from her hand
            roundCards gameAfterPlay `shouldBe` ["2H", "AH"]

            -- The card should be added to the current round's table
            let currentTable = curRound (head (gameHands gameAfterPlay))
            currentTable `shouldBe` ["3C"]

    describe "KingClient: Identity and Turn Management" $ do
        let pAlice = Player "Alice" "channel-123"
            initGame = mkGame pAlice "Table1" "secret-456"
            gameWPlayers = setPlayers initGame ["Alice", "Bob", "Charlie", "Dave"]

        it "moveTurn accurately resolves player names to their index" $ do
            let turnBob = moveTurn gameWPlayers "Bob"
            activeTurn turnBob `shouldBe` 1

            let turnDave = moveTurn turnBob "Dave"
            activeTurn turnDave `shouldBe` 3

        it "playCard removes the card from the local hand ONLY if it's the local player's turn" $ do
            -- The server says Bob is starting the hand
            let started = startHand gameWPlayers "Bob" [RVaza]
                -- Alice gets her cards
                withCards = setupCards started ["2H", "3C", "AH"]

            -- The server says Bob played "3C". 
            -- (Even if Alice happens to have that card, her hand shouldn't lose it because she isn't Bob).
            let afterBobPlays = playCard withCards "3C"

            -- Alice's hand is untouched
            roundCards afterBobPlays `shouldBe` ["2H", "3C", "AH"]
            -- But the table should show Bob's card
            curRound (head (gameHands afterBobPlays)) `shouldBe` ["3C"]

            -- Now the server says it is Alice's turn
            let aliceTurn = moveTurn afterBobPlays "Alice"
                afterAlicePlays = playCard aliceTurn "AH"

            -- Now Alice's hand SHOULD lose the card
            roundCards afterAlicePlays `shouldBe` ["2H", "3C"]
            -- And the table should have both
            curRound (head (gameHands afterAlicePlays)) `shouldBe` ["3C", "AH"]

    describe "KingClient: Hand Lifecycle" $ do
        let pAlice = Player "Alice" "ch1"
            gameWPlayers = setPlayers (mkGame pAlice "T1" "s") ["Alice", "Bob", "Charlie", "Dave"]

        it "startHand pushes a new hand with pending rules (Left) and sets the starter" $ do
            let started = startHand gameWPlayers "Charlie" [RVaza, RKing]

            activeTurn started `shouldBe` 2
            length (gameHands started) `shouldBe` 1
            handRule (head (gameHands started)) `shouldBe` Left [RVaza, RKing]

        it "setHandRule commits the pending rules to a chosen rule (Right)" $ do
            let started = startHand gameWPlayers "Charlie" [RVaza, RKing]
                committed = setHandRule started RKing

            handRule (head (gameHands committed)) `shouldBe` Right RKing

    describe "KingClient: Score Accumulation (endRound)" $ do
        let pAlice = Player "Alice" "ch1"
            gameWPlayers = setPlayers (mkGame pAlice "T1" "s") ["Alice", "Bob", "Charlie", "Dave"]
            started = startHand gameWPlayers "Alice" [RVaza]

            -- Simulate a table with 4 cards played
            tableFull = started { gameHands = [ (head (gameHands started)) { curRound = ["2H", "3H", "4H", "5H"] } ] }

        it "clears the table and attributes the score to the winning player's index" $ do
            -- The server declares Charlie (index 2) won the trick and took -20 points
            let postRound = endRound tableFull "Charlie" (-20)
                currentHand = head (gameHands postRound)

            -- The table cards should be swept away
            curRound currentHand `shouldBe` []

            -- The score should be appended to the score matrix. 
            -- replaceNth 2 (-20) [0,0,0,0] -> [0, 0, -20, 0]
            handScore currentHand `shouldBe` [[0, 0, -20, 0]]

        it "stacks multiple rounds of scoring correctly" $ do
            let r1 = endRound tableFull "Charlie" (-20)
                -- Simulate more cards being played and round 2 ending
                r2 = endRound r1 "Bob" (-50)
                currentHand = head (gameHands r2)

            -- We should have two score arrays in the history now
            handScore currentHand `shouldBe` [[0, 0, -20, 0], [0, -50, 0, 0]]

    ----------------------------------------------------------------------
    -- 5. SERVER LOGIC: USER AUTH AND TABLE MANAGEMENT
    ----------------------------------------------------------------------
    describe "ServerLogic: Identity and Table Management" $ do
        let emptyCtx = emptyServerContext

        describe "AUTHORIZE command" $ do
            it "authorizes a new user and returns a generated channel ID" $ do
                let (reply, bcast, ctx') = runCmd' emptyCtx ["AUTHORIZE", "Alice", "password123"] ["chan-A"]

                reply `shouldBe` "chan-A"
                bcast `shouldBe` []

        describe "TABLE command (Create Table)" $ do
            let (_, _, ctxAlice) = runCmd' emptyCtx ["AUTHORIZE", "Alice", "pass"] ["chan-A"]

            it "creates a new table and returns the table ID if the user is authorized" $ do
                let (reply, bcast, ctxTable) = runCmd' ctxAlice ["TABLE", "Alice", "chan-A"] ["table-1"]

                reply `shouldBe` "table-1"
                bcast `shouldBe` []

            it "returns an ERROR if the user provides the wrong channel ID" $ do
                let (reply, bcast, ctxTable) = runCmd ctxAlice ["TABLE", "Alice", "wrong-channel"]

                reply `shouldBe` "ERROR User not authorized"

        describe "JOIN command and Game Start Broadcast" $ do
            let ctx0 = emptyCtx
                -- 1. Alice Auths, Creates Table, AND Joins (Python's create_table doesn't auto-join)
                (_, _, ctxA)      = runCmd' ctx0 ["AUTHORIZE", "Alice", "pass"] ["chan-A"]
                (_, _, ctxT1)     = runCmd' ctxA ["TABLE", "Alice", "chan-A"] ["table-1"]
                (_, _, ctxA_Join) = runCmd' ctxT1 ["JOIN", "Alice", "chan-A", "table-1"] ["sec-A"]

                -- 2. Bob Auths & Joins
                (_, _, ctxB)      = runCmd' ctxA_Join ["AUTHORIZE", "Bob", "pass"] ["chan-B"]
                (_, _, ctxB_Join) = runCmd' ctxB ["JOIN", "Bob", "chan-B", "table-1"] ["sec-B"]

                -- 3. Cat Auths & Joins
                (_, _, ctxC)      = runCmd' ctxB_Join ["AUTHORIZE", "Cat", "pass"] ["chan-C"]
                (_, _, ctxC_Join) = runCmd' ctxC ["JOIN", "Cat", "chan-C", "table-1"] ["sec-C"]

                -- 4. Dave Auths
                (_, _, ctxD)      = runCmd' ctxC_Join ["AUTHORIZE", "Dave", "pass"] ["chan-D"]

            it "allows a second authorized user to join an existing table and returns a secret without broadcasting" $ do
                -- We test Bob joining against Alice's context
                let (reply, bcast, _) = runCmd' ctxB ["JOIN", "Bob", "chan-B", "table-1"] ["sec-B"]

                reply `shouldBe` "sec-B"
                bcast `shouldBe` []

            it "allows a third authorized user to join an existing table and returns a secret without broadcasting" $ do
                -- We test Cat joining against Alice's context
                let (reply, bcast, _) = runCmd' ctxC ["JOIN", "Cat", "chan-C", "table-1"] ["sec-C"]

                reply `shouldBe` "sec-C"
                bcast `shouldBe` []

            it "returns an ERROR if the table does not exist" $ do
                let (reply, _, _) = runCmd ctxB ["JOIN", "Bob", "chan-B", "ghost-table"]
                reply `shouldBe` "ERROR Table does not exist"

            it "allows a fourth user to join, returns a secret, and BROADCASTS the game start" $ do
                -- Dave joins a table that already has Alice, Bob, and Cat
                let (reply, bcast, _) = runCmd' ctxD ["JOIN", "Dave", "chan-D", "table-1"] ["sec-D"]

                reply `shouldBe`    "sec-D"
                bcast `shouldBe`    [ "table-1 START Alice Bob Cat Dave"
                                    -- Alice is player 0, so she starts the first hand.
                                    -- The server must send her name and the full list of initial rules.
                                    , "table-1 STARTHAND Alice VAZA HOMENS MULHERES 2ULTIMAS COPAS KING POSITIVA" 
                                    ]

            it "returns an ERROR if a fifth user tries to join a full table" $ do
                -- First, we officially add Dave to the timeline to fill the table
                let (_, _, ctxD_Join) = runCmd' ctxD ["JOIN", "Dave", "chan-D", "table-1"] ["sec-D"]
                    -- Now Eve tries to crash the party
                    (_, _, ctxE)      = runCmd' ctxD_Join ["AUTHORIZE", "Eve", "pass"] ["chan-E"]
                    (reply, _, _)     = runCmd ctxE ["JOIN", "Eve", "chan-E", "table-1"]

                reply `shouldBe` "ERROR Table is already full"

    ----------------------------------------------------------------------
    -- 6. SERVER LOGIC: GAME PROGRESSION
    ----------------------------------------------------------------------
    describe "ServerLogic: Game Progression (Hand Rule definition)" $ do
        let stackedDeck =   [ ["2H", "AH", "2C"]  -- Alice
                            , ["3H", "KC", "3D"]  -- Bob
                            , ["4H", "QC", "4D"]  -- Cat
                            , ["5H", "JC", "5D"]  -- Dave
                            ]
            (ctxStarted, tId) = setupStartedGame [stackedDeck]

        describe "Private Game State (GETHAND)" $ do
            it "returns a JSON array of cards directly to the requester without broadcasting" $ do
                -- Alice requests her hand
                let (reply, bcast, _) = runCmd ctxStarted ["GETHAND", "Alice", "sec-A"]

                -- The reply should be her pre-established cards for the environment
                reply `shouldBe` "[\"2H\", \"AH\", \"2C\"]"

                -- Security check: It MUST NOT broadcast the hand to the table
                bcast `shouldBe` []

            it "prevents cheating by rejecting GETHAND if the user and secret don't match" $ do
                -- Bob tries to request Alice's hand using his own secret
                let (reply, bcast, _) = runCmd ctxStarted ["GETHAND", "Alice", "sec-B"]

                reply `shouldBe` "ERROR User not at table" -- avoids telling that user gave wrong secret for enhanced security
                bcast `shouldBe` []

        describe "Rule Calling & State Transitions" $ do
            it "enforces that Player 0 (Alice) must choose the first rule" $ do
                -- Bob tries to call a rule out of turn
                let (replyB, _, _) = runCmd ctxStarted ["GAME", "Bob", "sec-B", "COPAS"]
                replyB `shouldBe` "ERROR Not your turn to choose a rule"

                -- Alice calls it correctly
                let (replyA, bcastA, _) = runCmd ctxStarted ["GAME", "Alice", "sec-A", "COPAS"]
                replyA `shouldBe` "ACK"
                bcastA `shouldBe` ["table-1 GAME COPAS", "table-1 TURN Alice"]

            it "behaviorally transitions the state so GAME cannot be called twice" $ do
                let (_, _, ctxPlaying) = runCmd ctxStarted ["GAME", "Alice", "sec-A", "COPAS"]

                -- Alice tries to change her mind and call VAZA immediately after
                let (reply, _, _) = runCmd ctxPlaying ["GAME", "Alice", "sec-A", "VAZA"]
                reply `shouldBe` "ERROR Game is not waiting for a rule"

            it "behaviorally prevents PLAY commands before a GAME rule is chosen" $ do
                -- Alice tries to play a card before choosing a rule
                let (reply, _, _) = runCmd ctxStarted ["PLAY", "Alice", "sec-A", "2H"]
                reply `shouldBe` "ERROR Game is not in trick-playing phase"

        describe "Action Security (validateTableAction)" $ do
            let (ctxStarted, tId) = setupStartedGame []

            it "rejects a GAME command if the player secret is incorrect" $ do
                -- Alice tries to call a rule but uses the wrong secret
                let (reply, _, _) = runCmd ctxStarted ["GAME", "Alice", "wrong-secret", "COPAS"]
                reply `shouldBe` "ERROR User not at table" -- avoids telling that user gave wrong secret for enhanced security

            it "rejects a PLAY command if the player secret is incorrect" $ do
                -- Fast forward to playing trick
                let (_, _, ctxPlaying) = runCmd ctxStarted ["GAME", "Alice", "sec-A", "COPAS"]
                let (reply, _, _) = runCmd ctxPlaying ["PLAY", "Alice", "wrong-secret", "2H"]
                reply `shouldBe` "ERROR User not at table"

            it "rejects commands from users not found at the table" $ do
                let (reply, _, _) = runCmd ctxStarted ["GAME", "Ghost", "sec-ghost", "COPAS"]
                reply `shouldBe` "ERROR User not at table"

        describe "Op-Log Eliminative Rule Enforcement (GAME)" $ do
            let dummyDeck = [ ["2H"], ["4C"], ["7D"], ["9S"] ]
                -- We only need 1 deck to initialize the table now
                (ctxStarted, _) = setupStartedGame [dummyDeck]

                -- Helper array to map turn index to the player's credentials and their micro-deck card
                players = [("Alice", "sec-A", "2H"), ("Bob", "sec-B", "4C"), ("Cat", "sec-C", "7D"), ("Dave", "sec-D", "9S")]
                
                -- We pass `dummyDeck` in as the next deck for every round
                e1 = playMicroHand ctxStarted players 0 "POSITIVA" dummyDeck
                e2 = playMicroHand e1         players 1 "HOMENS"   dummyDeck
                e3 = playMicroHand e2         players 2 "MULHERES" dummyDeck
                e4 = playMicroHand e3         players 3 "VAZA"     dummyDeck
            
            it "forces a player to pick a negative rule if they already used their Positiva" $ do
                -- Hand 5: Back to Alice. She tries to play POSITIVA again.
                let (replyFail, _, _) = runCmd e4 ["GAME", "Alice", "sec-A", "POSITIVA"]
                -- She is forced to pick a negative rule (e.g., COPAS)
                    (replySuccess, _, _) = runCmd e4 ["GAME", "Alice", "sec-A", "COPAS"]

                replyFail `shouldBe` "ERROR Rule not available for this player at this time"
                replySuccess `shouldBe` "ACK"
            
            it "enforces a negative rule can only be picked once" $ do
                -- Hand 5: Alice tries to call VAZA
                let (replyFail, _, c1) = runCmd e4 ["GAME", "Alice", "sec-A", "VAZA"]
                replyFail `shouldBe` "ERROR Rule not available for this player at this time"
                -- Hand 5: Alice calls COPAS as it wasn't before                
                let (replySuccess, _, c2) = runCmd e4 ["GAME", "Alice", "sec-A", "COPAS"]
                replySuccess `shouldBe` "ACK"

        describe "Positiva Auction Lifecycle (BID, DECIDE, TRUMP)" $ do
            let dummyDeck = [ ["2H", "3H"], ["4C", "5C"], ["6D", "7D"], ["8S", "9S"] ]
                (ctxStart, _) = setupStartedGame [dummyDeck]
                
                -- Alice calls POSITIVA. 
                (replyGame, bcastsGame, ctxBidding) = runCmd ctxStart ["GAME", "Alice", "sec-A", "POSITIVA"]

            it "starts the bidding by asking the next player for a bid" $ do
                replyGame `shouldBe` "ACK"
                -- Python protocol strictly emits just the BID request here
                bcastsGame `shouldBe` ["table-1 BID Bob"]

            it "rejects unauthorized or out-of-turn bids" $ do
                let (replyBadSec, _, _) = runCmd ctxBidding ["BID", "Bob", "wrong-sec", "2"]
                replyBadSec `shouldContain` "ERROR"
                
                let (replyEarly, _, _)  = runCmd ctxBidding ["BID", "Cat", "sec-C", "2"]
                replyEarly `shouldContain` "ERROR"

            it "loops multi-round bidding until 3 players pass (Red Flag Test)" $ do
                -- Round 1: Bob bids 2
                let (_, bcastsB1, c1) = runCmd ctxBidding ["BID", "Bob", "sec-B", "2"]
                bcastsB1 `shouldBe` ["table-1 BIDS 2", "table-1 BID Cat"]
                
                -- Cat passes (0)
                let (_, bcastsC1, c2) = runCmd c1 ["BID", "Cat", "sec-C", "0"]
                bcastsC1 `shouldBe` ["table-1 BIDS 0", "table-1 BID Dave"]
                
                -- Dave bids 3
                let (_, bcastsD1, c3) = runCmd c2 ["BID", "Dave", "sec-D", "3"]
                
                -- RED FLAG: Because Bob bid 2, and Dave raised to 3, the auction is NOT over!
                -- It must loop back to Bob to see if he wants to raise or pass.
                bcastsD1 `shouldBe` ["table-1 BIDS 3", "table-1 BID Bob"]
                
                -- Round 2: Bob gives up and passes
                let (replyB2, bcastsB2, _) = runCmd c3 ["BID", "Bob", "sec-B", "0"]
                replyB2 `shouldBe` "ACK"
                
                -- Now that Bob, Cat, and Dave have all either passed or placed the highest bid, 
                -- the auction ends and Alice must DECIDE.
                bcastsB2 `shouldBe` ["table-1 BIDS 0", "table-1 DECIDE Alice"]

            it "allows the caller to DECIDE and the winner to choose TRUMP" $ do
                -- We quickly simulate a 1-round auction where Dave wins with 3.
                let (_, _, c1) = runCmd ctxBidding ["BID", "Bob", "sec-B", "0"]
                    (_, _, c2) = runCmd c1 ["BID", "Cat", "sec-C", "0"]
                    (_, _, c3) = runCmd c2 ["BID", "Dave", "sec-D", "3"]
                
                -- Alice decides to ACCEPT Dave's bid
                let (replyDecide, bcastsDecide, c4) = runCmd c3 ["DECIDE", "Alice", "sec-A", "True"]
                replyDecide `shouldBe` "ACK"
                bcastsDecide `shouldBe` ["table-1 CHOOSETRUMP Dave"]
                
                -- Dave picks Hearts ('H')
                let (replyTrump, bcastsTrump, c5) = runCmd c4 ["TRUMP", "Dave", "sec-D", "H"]
                replyTrump `shouldBe` "ACK"
                bcastsTrump `shouldBe` ["table-1 GAME POSITIVA H", "table-1 TURN Alice"]
                
                -- Prove the state machine shifted to PlayingTrick by successfully playing the first card!
                let (replyPlay, _, _) = runCmd c5 ["PLAY", "Alice", "sec-A", "2H"]
                replyPlay `shouldBe` "ACK"

    ----------------------------------------------------------------------
    -- 7 SERVER LOGIC: TRICK PLAYING & RULE EVALUATION
    ----------------------------------------------------------------------
    describe "ServerLogic: Trick Playing & GameRules Integration" $ do
        -- We stack the deck so every player has at least one Heart (H) and one Club (C)
        let stackedDeck =   [ ["2H", "AH", "2C"]  -- Alice
                            , ["3H", "KC", "3D"]  -- Bob
                            , ["4H", "QC", "4D"]  -- Cat
                            , ["5H", "JC", "5D"]  -- Dave
                            ]

            (ctxStarted, tId) = setupStartedGame [stackedDeck]
            ctxPlaying = fromJust $ do
                -- Alice calls VAZA to start the hand
                (reply, _, ctx) <- Just $ runCmd ctxStarted ["GAME", "Alice", "sec-A", "VAZA"]
                if reply == "ACK" then Just ctx else Nothing
        

        describe "PLAY Validations (Hand and GameRules)" $ do
            it "rejects a PLAY command if the user does not have that card in their hand" $ do
                -- Alice tries to play the "9S" which is not in her dealt hand
                let (reply, _, _) = runCmd ctxPlaying ["PLAY", "Alice", "sec-A", "9S"]
                reply `shouldBe` "ERROR Card not in hand"

            it "rejects a PLAY command if it violates GameRules constraints (e.g., must follow suit)" $ do
                -- 1. Alice leads with a Club
                let (replyA, _, ctxTurn1) = runCmd ctxPlaying ["PLAY", "Alice", "sec-A", "2C"]
                replyA `shouldBe` "ACK"
                
                -- 2. It is Bob's turn. Bob has a Club ("KC"), but tries to play a Heart ("3H")
                let (reply, _, _) = runCmd ctxTurn1 ["PLAY", "Bob", "sec-B", "3H"]
                reply `shouldBe` "ERROR Invalid play: must follow suit"

        describe "PLAY State Transitions & GETHAND sync" $ do
            it "removes a successfully played card from the user's hand" $ do
                -- 1. Alice plays "2H"
                let (replyPlay, _, ctxTurn1) = runCmd ctxPlaying ["PLAY", "Alice", "sec-A", "2H"]
                replyPlay `shouldBe` "ACK"

                -- 2. Alice requests her hand. The "2H" should be gone.
                let (replyHand, _, _) = runCmd ctxTurn1 ["GETHAND", "Alice", "sec-A"]
                replyHand `shouldBe` "[\"AH\", \"2C\"]"

        describe "Trick Progression (Winner leads next trick)" $ do
            -- A 2-card micro-deck to test the transition between Trick 1 and Trick 2
            let deck = [ ["2H", "3H"], ["7H", "4H"], ["4C", "5C"], ["KH", "8D"] ]
                (ctxStarted, _) = setupStartedGame [deck]

                -- Start the hand with Alice picking VAZA. Alice leads the first trick.
                (_, _, c1) = runCmd ctxStarted ["GAME", "Alice", "sec-A", "VAZA"]
                
                -- Play the first 3 cards of Trick 1
                (_, _, c2) = runCmd c1 ["PLAY", "Alice", "sec-A", "2H"]
                (_, _, c3) = runCmd c2 ["PLAY", "Bob", "sec-B", "7H"]
                (_, _, c4) = runCmd c3 ["PLAY", "Cat", "sec-C", "4C"]
                
            it "broadcasts ENDROUND and TURN to the winner, making them the active player" $ do
                -- Dave plays the 4th card, completing Trick 1
                let (reply, bcasts, c5) = runCmd c4 ["PLAY", "Dave", "sec-D", "KH"]                
                reply `shouldBe` "ACK"
                
                -- Dave won the trick because KH is the highest Heart (the led suit).
                bcasts `shouldContain` ["table-1 PLAY KH"]
                bcasts `shouldContain` ["table-1 ENDROUND Dave -20"] 
                bcasts `shouldContain` ["table-1 TURN Dave"]
                                    
                -- Prove Dave is now the active player for Trick 2 (Instead of Bob, the next after Alice)
                let (replyBob, _, _) = runCmd c5 ["PLAY", "Dave", "sec-D", "8D"]
                replyBob `shouldBe` "ACK"
                
                -- Prove Alice (the original starter) cannot play out of turn
                let (replyAlice, _, _) = runCmd c5 ["PLAY", "Alice", "sec-A", "3H"]
                replyAlice `shouldContain` "ERROR"

        describe "Trick Completion and Winner Evaluation" $ do
            it "evaluates the trick after 4 cards, awards points, and gives the winner the next turn" $ do
                -- Play out a full trick of Hearts
                let (_, _, ctxT1) = runCmd ctxPlaying ["PLAY", "Alice", "sec-A", "2H"]
                    (_, _, ctxT2) = runCmd ctxT1 ["PLAY", "Bob", "sec-B", "3H"]
                    (_, _, ctxT3) = runCmd ctxT2 ["PLAY", "Cat", "sec-C", "4H"]
                    
                    -- Dave plays the 5H. This is the 4th card, which should trigger trick evaluation.
                    (replyT4, _, ctxT4) = runCmd ctxT3 ["PLAY", "Dave", "sec-D", "5H"]
                    
                replyT4 `shouldBe` "ACK"
                
                -- The trick should clear, so it's ready for the next round
                -- (We test this behaviorally: if Dave plays again, it's a new lead)
                let (replyLead, _, _) = runCmd ctxT4 ["PLAY", "Dave", "sec-D", "JC"]
                replyLead `shouldBe` "ACK"
                
                -- If Alice tried to play, it would fail because Dave won the trick and gets the lead
                let (replyFail, _, _) = runCmd ctxT4 ["PLAY", "Alice", "sec-A", "AH"]
                replyFail `shouldBe` "ERROR Not your turn"

        describe "Trick Completion and Multiple Broadcasts (PLAY)" $ do
            it "broadcasts ONLY the PLAY/TURN events for the first 3 cards of a trick" $ do
                -- 1st card
                let (reply1, bcasts1, _) = runCmd' ctxPlaying ["PLAY", "Alice", "sec-A", "2H"] []
                reply1 `shouldBe` "ACK"
                bcasts1 `shouldBe` ["table-1 PLAY 2H", "table-1 TURN Bob"] -- Bob gets the turn after Alice's lead
                
                -- 2nd card
                let (_, _, ctxT1) = runCmd' ctxPlaying ["PLAY", "Alice", "sec-A", "2H"] []
                    (reply2, bcasts2, _) = runCmd' ctxT1 ["PLAY", "Bob", "sec-B", "3H"] []
                reply2 `shouldBe` "ACK"
                bcasts2 `shouldBe` ["table-1 PLAY 3H", "table-1 TURN Cat"] -- Cat gets the turn after Bob

            it "broadcasts both PLAY and ENDROUND events when the 4th card is played" $ do
                let (_, _, ctxT1) = runCmd' ctxPlaying ["PLAY", "Alice", "sec-A", "2H"] []
                    (_, _, ctxT2) = runCmd' ctxT1 ["PLAY", "Bob", "sec-B", "3H"] []
                    (_, _, ctxT3) = runCmd' ctxT2 ["PLAY", "Cat", "sec-C", "4H"] []
                    
                    -- Dave plays the 4th card, resolving the trick.
                    (replyT4, bcastsT4, _) = runCmd' ctxT3 ["PLAY", "Dave", "sec-D", "5H"] []
                    
                replyT4 `shouldBe` "ACK"
                
                -- The sequence is critical: clients need to see the card hit the table BEFORE the trick resolves
                bcastsT4 `shouldBe` [ "table-1 PLAY 5H"
                                    , "table-1 ENDROUND Dave -20" -- Dave wins the trick with the highest Heart and gets -20 points in Vaza
                                    , "table-1 TURN Dave"
                                    ]

        describe "Hand Completion and Multiple Broadcasts (Short-Circuit via RKing)" $ do
            -- We stack a specific deck for the King rule.
            -- Alice will lead a Heart, and Bob will be forced to play the King of Hearts.
            let kingDeck = [ ["2H", "3C"]  -- Alice
                            , ["KH", "4D"]  -- Bob
                            , ["3H", "5C"]  -- Cat
                            , ["4H", "6C"]  -- Dave
                            ]
                (ctxKing, _) = setupStartedGame [kingDeck]
                ctxPlaying = fromJust $ do
                    (reply, _, ctx) <- Just $ runCmd ctxKing ["GAME", "Alice", "sec-A", "KING"]
                    if reply == "ACK" then Just ctx else Nothing

            it "broadcasts PLAY, ENDROUND, and ENDHAND immediately when the King of Hearts trick resolves" $ do
                -- 1. Alice leads a low Heart
                let (_, _, ctxT1) = runCmd' ctxPlaying ["PLAY", "Alice", "sec-A", "3C"] []                
                -- 2. Bob plays the King of Hearts
                let (_, _, ctxT2) = runCmd' ctxT1 ["PLAY", "Bob", "sec-B", "KH"] []                
                -- 3. Cat plays a Heart
                let (_, _, ctxT3) = runCmd' ctxT2 ["PLAY", "Cat", "sec-C", "5C"] []                
                -- 4. Dave plays the final card of the trick
                let (replyT4, bcastsT4, _) = runCmd' ctxT3 ["PLAY", "Dave", "sec-D", "6C"] []
                replyT4 `shouldBe` "ACK"
                
                -- Because the King of Hearts was in the trick, the hand is instantly over!
                -- Bob takes the trick (highest heart), and the game moves to the next hand.
                bcastsT4 `shouldBe` [ "table-1 PLAY 6C"
                                    , "table-1 ENDROUND Dave -160" -- Dave wins the trick with the King of Hearts and gets -160 points in King
                                    , "table-1 ENDHAND 0 0 0 -160"
                                    , "table-1 STARTHAND Bob VAZA HOMENS MULHERES 2ULTIMAS COPAS POSITIVA"
                                    ]

        describe "Game Termination (GAMEOVER Protocol via Micro-Decks)" $ do
            -- A generic 1-card deck for the first 9 hands. 
            -- Deal order: Alice gets 2H, Bob 4C, Cat 7D, Dave 9S.            
            let dummyDeck = [ ["KH"], ["4C"], ["7D"], ["9S"] ]
                -- We only need 1 deck to initialize the table now
                (ctxStart, _) = setupStartedGame [dummyDeck]

                -- Helper array to map turn index to the player's credentials and their micro-deck card
                players = [("Alice", "sec-A", "KH"), ("Bob", "sec-B", "4C"), ("Cat", "sec-C", "7D"), ("Dave", "sec-D", "9S")]

                -- We pass `dummyDeck` in as the next deck for every round

                -- Play 9 hands instantly! 
                -- Turn starter naturally advances: 0 -> 1 -> 2 -> 3 -> 0 -> 1 -> 2 -> 3 -> 0
                e1 = playMicroHand ctxStart players 0 "VAZA" dummyDeck      -- [-20 0 0 0]
                e2 = playMicroHand e1       players 1 "HOMENS" dummyDeck    -- [-20 -30 0 0]
                e3 = playMicroHand e2       players 2 "MULHERES" dummyDeck  -- [-20 -30 0 0]
                e4 = playMicroHand e3       players 3 "2ULTIMAS" dummyDeck  -- [-20 -30 0 -90]
                e5 = playMicroHand e4       players 0 "COPAS" dummyDeck     -- [-40 -30 0 -90]
                e6 = playMicroHand e5       players 1 "POSITIVA" dummyDeck  -- [-40 -5 0 -90]
                e7 = playMicroHand e6       players 2 "POSITIVA" dummyDeck  -- [-40 -5 25 -90]
                e8 = playMicroHand e7       players 3 "POSITIVA" dummyDeck  -- [-40 -5 25 -65]
                e9 = playMicroHand e8       players 0 "POSITIVA" dummyDeck  -- [-15 -5 25 -65]
                -- Hand 9 naturally finished. Bob (Index 1) is up next for Hand 10.
                
            it "broadcasts GAMEOVER instead of STARTHAND when the 10th and final hand resolves" $ do
                -- Hand 10: Bob leads. Rule must be KING.
                let (_, _, ctxKing) = runCmd e9 ["GAME", "Bob", "sec-B", "KING"]
                let (_, _, ctxT1) = runCmd ctxKing ["PLAY", "Bob", "sec-B", "4C"]
                let (_, _, ctxT2) = runCmd ctxT1 ["PLAY", "Cat", "sec-C", "7D"]
                let (_, _, ctxT3) = runCmd ctxT2 ["PLAY", "Dave", "sec-D", "9S"]
                let (reply, bcasts, _) = runCmd ctxT3 ["PLAY", "Alice", "sec-A", "KH"]

                reply `shouldBe` "ACK"

                -- Bob played the KH (the highest heart in this trick), so he wins the trick and gets the -160.
                bcasts `shouldBe` [ "table-1 PLAY KH"
                                , "table-1 ENDROUND Bob -160"
                                , "table-1 ENDHAND 0 -160 0 0"
                                , "table-1 GAMEOVER -15 -165 25 -65" -- Not ideal but needed (not ideal because test is peering into the rules to replicate server calculations)
                                ]

    describe "Utility Commands (LIST, GETTURN, LEAVE)" $ do
        -- Setup an empty lobby with two players
        let c0 = emptyServerContext
            (_, _, cA)  = runCmd' c0 ["AUTHORIZE", "Alice", "pass"] ["chan-A"]
            (_, _, cT1) = runCmd' cA ["TABLE", "Alice", "chan-A"] ["table-1"]
            (_, _, cJ1) = runCmd' cT1 ["JOIN", "Alice", "chan-A", "table-1"] ["sec-A"]
            (_, _, cB)  = runCmd' cJ1 ["AUTHORIZE", "Bob", "pass"] ["chan-B"]
            (_, _, lobbyCtx) = runCmd' cB ["JOIN", "Bob", "chan-B", "table-1"] ["sec-B"]

        -- Setup a fully started game
        let dummyDeck = [ ["2H", "3H"], ["4C", "5C"], ["6D", "7D"], ["8S", "9S"] ]
            (startedCtx, _) = setupStartedGame [dummyDeck]

        it "LIST: returns a JSON array of active tables and their players" $ do
            let (reply, _, _) = runCmd lobbyCtx ["LIST"]
            -- Expecting something like: [{"name": "table-1", "players": ["Alice", "Bob"]}]
            reply `shouldContain` "\"name\": \"table-1\""
            reply `shouldContain` "\"Alice\""
            reply `shouldContain` "\"Bob\""

        it "GETTURN: returns the name of the active player" $ do
            -- In a newly started game, it is the starter's turn to pick a rule
            let (reply, _, _) = runCmd startedCtx ["GETTURN", "Alice", "sec-A"]
            reply `shouldBe` "Alice"

        it "LEAVE (Lobby): gracefully removes a player without destroying the table" $ do
            let (reply, bcasts, ctxAfterLeave) = runCmd lobbyCtx ["LEAVE", "Bob", "sec-B"]
            
            reply `shouldBe` "ACK"
            bcasts `shouldBe` ["table-1 LEAVE Bob"]
            
            -- Verify the table still exists but Bob is gone
            let (listReply, _, _) = runCmd ctxAfterLeave ["LIST"]
            listReply `shouldContain` "table-1"
            listReply `shouldContain` "\"Alice\""
            listReply `shouldNotContain` "\"Bob\""

        it "LEAVE (Started): destroys the table and broadcasts GAMEOVER to remaining players" $ do
            -- Cat rage-quits after the game starts
            let (reply, bcasts, ctxAfterRageQuit) = runCmd startedCtx ["LEAVE", "Cat", "sec-C"]
            
            reply `shouldBe` "ACK"
            -- LEAVE followed immediately by GAMEOVER with the current scores
            bcasts `shouldBe` [ "table-1 LEAVE Cat"
                                , "table-1 GAMEOVER 0 0 0 0"
                                ]
                                
            -- Verify the table was completely purged from the server memory
            let (listReply, _, _) = runCmd ctxAfterRageQuit ["LIST"]
            listReply `shouldBe` "[]"

    describe "Global Matchmaking (LISTUSERS, AVAILABLE, FINISHLIST, MATCH)" $ do
        let c0 = emptyServerContext
            -- Authorize 5 players so the server knows their channels
            (_, _, c1) = runCmd' c0 ["AUTHORIZE", "Alice", "pass"] ["chan-A"]
            (_, _, c2) = runCmd' c1 ["AUTHORIZE", "Bob", "pass"] ["chan-B"]
            (_, _, c3) = runCmd' c2 ["AUTHORIZE", "Cat", "pass"] ["chan-C"]
            (_, _, c4) = runCmd' c3 ["AUTHORIZE", "Dave", "pass"] ["chan-D"]
            (_, _, ctxAuth) = runCmd' c4 ["AUTHORIZE", "Eve", "pass"] ["chan-E"]

        it "LISTUSERS: starts the poll and asks everyone if they are available" $ do
            let (reply, bcasts, _) = runCmd ctxAuth ["LISTUSERS"]
            
            reply `shouldBe` "ACK"
            -- It must ping every single authorized user's channel
            bcasts `shouldContain` ["chan-A CONFIRM_AVAILABLE"]
            bcasts `shouldContain` ["chan-B CONFIRM_AVAILABLE"]
            bcasts `shouldContain` ["chan-C CONFIRM_AVAILABLE"]
            bcasts `shouldContain` ["chan-D CONFIRM_AVAILABLE"]
            bcasts `shouldContain` ["chan-E CONFIRM_AVAILABLE"]

        it "AVAILABLE: records a user if a poll is active, rejects if timed out" $ do
            let (_, _, ctxPolling) = runCmd ctxAuth ["LISTUSERS"]
            
            -- Bob and Cat reply in time
            let (replyBob, _, cB) = runCmd ctxPolling ["AVAILABLE", "Bob", "chan-B"]
                (replyCat, _, _)  = runCmd cB ["AVAILABLE", "Cat", "chan-C"]
                
            replyBob `shouldBe` "ACK"
            replyCat `shouldBe` "ACK"
            
            -- If Eve tries to reply to the base context (where no poll is running), she is rejected
            let (replyEveTimeout, _, _) = runCmd ctxAuth ["AVAILABLE", "Eve", "chan-E"]
            replyEveTimeout `shouldBe` "ERROR Timeout on response"

        it "FINISHLIST: ends the poll and broadcasts the active users" $ do
            let (_, _, ctxPolling) = runCmd ctxAuth ["LISTUSERS"]
                (_, _, cB) = runCmd ctxPolling ["AVAILABLE", "Bob", "chan-B"]
                (_, _, cC) = runCmd cB ["AVAILABLE", "Cat", "chan-C"]
                (_, _, cD) = runCmd cC ["AVAILABLE", "Dave", "chan-D"]
                
                -- The server timer pops and triggers this internal command
                (reply, bcasts, _) = finishList cD
                
            reply `shouldBe` "ACK"
            -- The server broadcasts the collected list to the global matchmaking channel
            bcasts `shouldBe` ["user-list-channel Bob Cat Dave"]

        it "MATCH: creates a table and sends ASKJOIN to the requested active players" $ do
            let (_, _, ctxPolling) = runCmd ctxAuth ["LISTUSERS"]
                (_, _, cB) = runCmd ctxPolling ["AVAILABLE", "Bob", "chan-B"]
                (_, _, cC) = runCmd cB ["AVAILABLE", "Cat", "chan-C"]
                (_, _, cD) = runCmd cC ["AVAILABLE", "Dave", "chan-D"]
                -- The list finishes
                (_, _, ctxReady) = finishList cD
                
                -- Alice asks to form a match with Bob, Cat, and Dave
                (replyMatch, bcastsMatch, _) = runCmd' ctxReady ["MATCH", "Alice", "chan-A", "Bob", "Cat", "Dave"] ["table-new"]

            -- The reply should be the generated table ID
            replyMatch `shouldBe` "table-new"
            
            -- The server must send direct messages to Bob, Cat, and Dave inviting them to the new table
            bcastsMatch `shouldContain` ["chan-B ASKJOIN table-new"]
            bcastsMatch `shouldContain` ["chan-C ASKJOIN table-new"]
            bcastsMatch `shouldContain` ["chan-D ASKJOIN table-new"]
            
            -- It should NOT invite Alice (she is already the creator) or Eve (she wasn't invited/available)
            bcastsMatch `shouldNotContain` ["chan-A ASKJOIN"]
            bcastsMatch `shouldNotContain` ["chan-E ASKJOIN"]

        it "MATCH: fails if players are not in the active list or wrong count" $ do
            let (_, _, ctxPolling) = runCmd ctxAuth ["LISTUSERS"]
                (_, _, ctxReady) = finishList ctxPolling-- Finished with NO available players
                
                (replyFail, _, _) = runCmd ctxReady ["MATCH", "Alice", "chan-A", "Bob", "Cat", "Dave"]
                
            replyFail `shouldBe` "ERROR You must inform 3 or 4 other valid players"
