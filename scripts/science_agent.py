import json
import subprocess
import random
import time
import os
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed

BOT_POOL_FILE = "scripts/bot_pool.json"
STATS_FILE = "scripts/bot_stats.json"
MAX_CONCURRENT_MATCHES = 8 # Balanced for performance and stability
MATCH_TIMEOUT = 300 # 5 minutes per match should be plenty for bots

def load_bots():
    with open(BOT_POOL_FILE, 'r') as f:
        return json.load(f)

def load_stats():
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError:
            pass
    return {}

def save_stats(stats):
    with open(STATS_FILE, 'w') as f:
        json.dump(stats, f, indent=2)

def run_match_custom(cmd):
    try:
        # Added timeout to prevent hung processes from stalling the pipeline
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=MATCH_TIMEOUT)
        lines = result.stdout.splitlines()
        for line in lines:
            if line.startswith("RESULT:"):
                return line.replace("RESULT:", "").strip()
    except subprocess.TimeoutExpired:
        print(f"Match TIMEOUT: {cmd[1]}")
    except subprocess.CalledProcessError as e:
        print(f"Match FAILED: {cmd[1]} - {e.stderr}")
    except Exception as e:
        print(f"Match ERROR: {str(e)}")
    return None

def update_stats(stats, result_line):
    if not result_line: return
    
    # Format: Bot_Name1_iX:Score1 Bot_Name2_iX:Score2 ...
    parts = result_line.strip().split()
    match_results = []
    for part in parts:
        try:
            full_name, score = part.split(':')
            name = full_name.rsplit('_i', 1)[0]
            score = int(score)
            match_results.append((name, score))
            
            if name not in stats:
                stats[name] = {"games": 0, "total_score": 0, "wins": 0}
            
            stats[name]["games"] += 1
            stats[name]["total_score"] += score
        except ValueError:
            continue
        
    if match_results:
        winner_name = max(match_results, key=lambda x: x[1])[0]
        stats[winner_name]["wins"] += 1

def main():
    bots = load_bots()
    stats = load_stats()
    match_count = 0
    global_instance_id = 0
    
    print(f"Science Agent started with {MAX_CONCURRENT_MATCHES} workers.")
    print("Press Ctrl+C to stop and save.")
    
    with ProcessPoolExecutor(max_workers=MAX_CONCURRENT_MATCHES) as executor:
        # Initial fill
        futures = {}
        for _ in range(MAX_CONCURRENT_MATCHES):
            match_count += 1
            selected = random.sample(bots, 4)
            bot_args = []
            for b in selected:
                global_instance_id += 1
                bot_args.append(f"{b['name']}_i{global_instance_id},{b['risk']},{b['social']}")
            
            log_dir = f"scripts/logs/m{match_count}"
            cmd = ["./scripts/run_match.sh", f"Match_{match_count}", log_dir] + bot_args
            futures[executor.submit(run_match_custom, cmd)] = match_count

        try:
            while futures:
                for future in as_completed(futures):
                    m_id = futures.pop(future)
                    result = future.result()
                    if result:
                        update_stats(stats, result)
                        save_stats(stats)
                        print(f"[{time.strftime('%H:%M:%S')}] Match {m_id} FINISHED. Total games recorded: {sum(s['games'] for s in stats.values()) // 4}", flush=True)
                    
                    # Spawn next match to replace the completed one
                    match_count += 1
                    selected = random.sample(bots, 4)
                    bot_args = []
                    for b in selected:
                        global_instance_id += 1
                        bot_args.append(f"{b['name']}_i{global_instance_id},{b['risk']},{b['social']}")
                    
                    log_dir = f"scripts/logs/m{match_count}"
                    cmd = ["./scripts/run_match.sh", f"Match_{match_count}", log_dir] + bot_args
                    futures[executor.submit(run_match_custom, cmd)] = match_count
                    
                    # Print Leaderboard every 10 matches
                    if match_count % 10 == 0:
                        ranked = sorted(stats.items(), key=lambda x: x[1]["wins"] / x[1]["games"] if x[1]["games"] > 0 else 0, reverse=True)
                        print("\n--- Current Top 5 Bots ---", flush=True)
                        for name, s in ranked[:5]:
                            wr = (s["wins"]/s["games"])*100 if s["games"] > 0 else 0
                            print(f"{name:20} | WR: {wr:5.1f}% | Avg: {s['total_score']/s['games']:7.1f} | G: {s['games']}", flush=True)
                        print("-" * 30 + "\n", flush=True)

        except KeyboardInterrupt:
            print("\nStopping Science Agent...")
            save_stats(stats)
            print("Stats saved.")

if __name__ == "__main__":
    main()
