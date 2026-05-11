#!/bin/bash

# Usage: ./run_match.sh <TableID> <LogDir> <Bot1JSON> <Bot2JSON> <Bot3JSON> <Bot4JSON>
# BotJSON is a comma-separated string: name,risk,social

TABLE_ID=$1
LOG_DIR=$2
shift 2

mkdir -p "$LOG_DIR"

# Path to the executable
EXE="./src/haskell/king-game/dist-newstyle/build/aarch64-osx/ghc-9.10.1/king-game-0.1.0.0/x/king-game-client-exe/build/king-game-client-exe/king-game-client-exe"

# If the executable doesn't exist at the specific path, try using cabal run
if [ ! -f "$EXE" ]; then
    EXE="cabal run --project-dir src/haskell/king-game king-game-client-exe --"
fi

PIDS=()

# Launch each bot
for BOT_DATA in "$@"; do
    IFS=',' read -r NAME RISK SOC <<< "$BOT_DATA"
    echo "Spawning $NAME (Risk: $RISK, Soc: $SOC) at $TABLE_ID"
    $EXE "$NAME" "$NAME" "$RISK" "$SOC" "$TABLE_ID" > "${LOG_DIR}/${NAME}.log" 2>&1 &
    PIDS+=($!)
    sleep 1.0 
done

# Wait for all bots to finish
for PID in "${PIDS[@]}"; do
    wait $PID
done

# Give some time for files to flush
sleep 1

# Collect results from logs
echo "MATCH_FINISHED: $TABLE_ID"
RESULT_LINE=$(grep -h "RESULT:" "$LOG_DIR"/*.log | head -n 1)
if [ -z "$RESULT_LINE" ]; then
    echo "ERROR: No result found for $TABLE_ID"
else
    echo "$RESULT_LINE"
fi

# Cleanup
rm -rf "$LOG_DIR"
