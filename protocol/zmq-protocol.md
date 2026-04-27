# King Communication Protocol (ZMQ)

This document specifies the text-based communication protocol used by the open King ecosystem. The communication is based on **ZeroMQ (ZMQ)** using two main patterns:
1.  **REQ/REP (Request/Response):** For synchronous actions like joining a table, getting your hand, or playing a card.
2.  **PUB/SUB (Publish/Subscribe):** For asynchronous game state updates, turn notifications, and match-making events.

---

## 🏗️ Connection Details

*   **Action Port (REQ/REP):** `tcp://<server-ip>:5555`
*   **Status Port (PUB/SUB):** `tcp://<server-ip>:5556`

All messages are space-separated strings.

---

## 🔐 Authentication & Session

Before performing any game actions, a user must authorize with the server.

### `AUTHORIZE <username> <password>` (REQ)
*   **Description:** Authenticates a user.
*   **Response:** `<channel_uuid>` (Session Channel) or `ERROR ...`
*   **Usage:** The returned `channel_uuid` is required for match-making and joining tables. It is also used as a SUB filter for private notifications.

---

## 🤝 Matchmaking & Table Management

### `LIST` (REQ)
*   **Description:** Lists all active tables.
*   **Response:** JSON array of table objects: `[{"name": "...", "players": ["p1", ...]}, ...]`

### `TABLE <username> <channel>` (REQ)
*   **Description:** Creates a new game table.
*   **Response:** `<table_uuid>` or `ERROR ...`

### `MATCH <username> <channel> <user2> <user3> <user4>` (REQ)
*   **Description:** Initiates a match with specific users.
*   **Response:** `<table_uuid>` or `ERROR ...`
*   **Note:** Triggers an `ASKJOIN` via PUB/SUB to the invited users.

### `JOIN <username> <channel> <table_uuid>` (REQ)
*   **Description:** Joins an existing table.
*   **Response:** `<player_secret>` or `ERROR ...`
*   **Note:** The `player_secret` is required for all game-play actions within that specific table.

---

## 🃏 In-Game Actions (REQ/REP)

These actions require `<username>` and the `<player_secret>` obtained during `JOIN`.

### `GETHAND <username> <secret>`
*   **Response:** JSON array of cards: `["AH", "10C", "7S", ...]`

### `GETTURN <username> <secret>`
*   **Response:** `<username>` of the player whose turn it is.

### `GAME <username> <secret> <rule>`
*   **Description:** Chooses the game rule for the current hand (only if it's the player's turn to choose).
*   **Rules:** `VAZA`, `HOMENS`, `MULHERES`, `2ULTIMAS`, `COPAS`, `KING`, `POSITIVA`.

### `BID <username> <secret> <value>`
*   **Description:** Submits a bid during a Positive round bidding phase.

### `DECIDE <username> <secret> <True|False>`
*   **Description:** Decides whether to accept the winning bid (True) or let the bidder take the Positive.

### `TRUMP <username> <secret> [suit]`
*   **Description:** Chooses the trump suit for a Positive hand.
*   **Suits:** `H` (Hearts), `D` (Diamonds), `C` (Clubs), `S` (Spades).

### `PLAY <username> <secret> <card>`
*   **Description:** Plays a card.
*   **Card Format:** `<Rank><Suit>` (e.g., `AH` for Ace of Hearts, `10C` for 10 of Clubs, `7S` for 7 of Spades).

---

## 📡 Game Updates (PUB/SUB)

Clients should subscribe to the `<table_uuid>` for general game updates and to their private `<channel_uuid>` for private prompts.

### Table Updates (Filter: `<table_uuid>`)

*   `<table_uuid> START <p1> <p2> <p3> <p4>`: Game has started.
*   `<table_uuid> STARTHAND <starter_name> <rule1> <rule2> ...`: A new hand is starting. Lists available rules for the starter.
*   `<table_uuid> TURN <username>`: It is now this player's turn to play.
*   `<table_uuid> BID <username>`: It is now this player's turn to bid.
*   `<table_uuid> BIDS <value>`: A player has made a bid.
*   `<table_uuid> GAME <rule> [trump]`: The game rule and optional trump have been selected.
*   `<table_uuid> PLAY <card>`: A player has played a card.
*   `<table_uuid> ENDROUND <winner_name> <score>`: A trick has ended.
*   `<table_uuid> ENDHAND <s1> <s2> <s3> <s4>`: A hand has ended. Scores for the hand are provided.
*   `<table_uuid> GAMEOVER <final_s1> <final_s2> <final_s3> <final_s4>`: The match is finished.
*   `<table_uuid> LEAVE <username>`: A player has left, and the table is closed.

### Private Updates (Filter: `<channel_uuid>`)

*   `<channel_uuid> ASKJOIN <table_uuid>`: Prompt to join a table created via `MATCH`.
*   `<channel_uuid> CONFIRM_AVAILABLE`: Ping from server to check if user is still active (used for `LISTUSERS`).
