import json
import subprocess
import random
import time
import os
import sys
from concurrent.futures import ProcessPoolExecutor

BOT_POOL_FILE = "scripts/bot_pool.json"
STATS_FILE = "scripts/bot_stats.json"
MAX_CONCURRENT_MATCHES = 2 # Keep it low to not kill the machine

def load_bots():
    with open(BOT_POOL_FILE, 'r') as f:
        return json.load(f)

def load_stats():
    if os.path.exists(STATS_FILE):
        with open(STATS_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_stats(stats):
    with open(STATS_FILE, 'w') as f:
        json.dump(stats, f, indent=2)

def run_match_custom(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lines = result.stdout.splitlines()
        for line in lines:
            if line.startswith("RESULT:"):
                return line.replace("RESULT:", "").strip()
    except subprocess.CalledProcessError as e:
        print(f"Match failed: {e.stderr}")
    return None

def update_stats(stats, result_line):
    # Format: Bot_Name1_iX:Score1 Bot_Name2_iX:Score2 ...
    parts = result_line.strip().split()
    match_results = []
    for part in parts:
        full_name, score = part.split(':')
        # Strip the _iX suffix
        name = full_name.rsplit('_i', 1)[0]
        score = int(score)
        match_results.append((name, score))
        
        if name not in stats:
            stats[name] = {"games": 0, "total_score": 0, "wins": 0}
        
        stats[name]["games"] += 1
        stats[name]["total_score"] += score
        
    # Determine winner of this match (using the stripped names)
    winner_name = max(match_results, key=lambda x: x[1])[0]
    stats[winner_name]["wins"] += 1

def main():
    bots = load_bots()
    stats = load_stats()
    match_count = 0
    global_instance_id = 0
    
    print("Science Agent started. Press Ctrl+C to stop and save.")
    
    try:
        while True:
            # Batch of matches
            futures = []
            with ProcessPoolExecutor(max_workers=MAX_CONCURRENT_MATCHES) as executor:
                for _ in range(MAX_CONCURRENT_MATCHES):
                    match_count += 1
                    selected = random.sample(bots, 4)
                    
                    # Give bots truly unique names for this match instance
                    bot_args = []
                    for b in selected:
                        global_instance_id += 1
                        bot_args.append(f"{b['name']}_i{global_instance_id},{b['risk']},{b['social']}")
                    
                    log_dir = f"scripts/logs/m{match_count}"
                    cmd = ["./scripts/run_match.sh", f"Match_{match_count}", log_dir] + bot_args
                    print(f"Starting Match {match_count} with {[b['name'] for b in selected]}")
                    futures.append(executor.submit(run_match_custom, cmd))
                
                for future in futures:
                    result = future.result()
                    if result:
                        update_stats(stats, result)
                        print(f"Match Result recorded: {result}")
            
            save_stats(stats)
            # Rank bots
            ranked = sorted(stats.items(), key=lambda x: x[1]["wins"] / x[1]["games"] if x[1]["games"] > 0 else 0, reverse=True)
            print("\n--- Current Top Bots (Hardest) ---")
            for name, s in ranked[:5]:
                win_rate = (s["wins"]/s["games"])*100 if s["games"] > 0 else 0
                print(f"{name}: {win_rate:.1f}% win rate ({s['games']} games)")
            
    except KeyboardInterrupt:
        print("\nStopping Science Agent...")
        save_stats(stats)
        print("Stats saved to scripts/bot_stats.json")

if __name__ == "__main__":
    main()
