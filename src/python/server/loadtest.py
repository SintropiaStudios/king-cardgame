#!/usr/bin/env python3
import sys
import os
import atexit
import time
import subprocess

# Add client directory to path to find client.py
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'client')))
import client

NUM_CLIENTS = 4
SPAWN_RATE = 600 #PER MINUTE

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(BASE_DIR, "server.py")
CLIENT = os.path.join(BASE_DIR, "..", "bot", "random_bot.py")
PYTHON_EXEC = sys.executable if sys.platform != 'win32' else "python.exe"
SERVER_PROC = None
CLIENTS = []

def cleanup():
    """ Handler for test termination """
    if SERVER_PROC:
        SERVER_PROC.terminate()

    time.sleep(1)
    for proc in CLIENTS:
        proc.terminate()

if __name__ == "__main__":
    NO_SERVER_OPT = False

    if len(sys.argv) > 1:
        NUM_CLIENTS = int(sys.argv[1])
        if len(sys.argv) > 2:
            NO_SERVER_OPT = sys.argv[2] == "--noserver"

    if not NO_SERVER_OPT:
        print("Starting Server")
        LOG_SERVER = open("./logs/log_server.log", "w")
        SERVER_PROC = subprocess.Popen([PYTHON_EXEC, SERVER], stdout=LOG_SERVER)

    atexit.register(cleanup)
    try:
        for c in range(NUM_CLIENTS):
            print("Starting Client", c)
            log_c = open("./logs/logC%d.log"%(c), "w")
            CLIENTS.append(subprocess.Popen([PYTHON_EXEC, CLIENT, str(c), str(c)], stdout=log_c))
            time.sleep(60./SPAWN_RATE)

        # Registers a match maker
        time.sleep(10) # Wait for clients to authorize
        print("Starting match maker")
        match_maker = client.Server('match_maker')
        match_maker.authorize('secret', lambda s, n: None)
        match_maker.pubsrv.setsockopt_string(client.zmq.SUBSCRIBE, 'user-list-channel')
        candidates = match_maker.get_user_list()
        print("List of candidates:", candidates)
        if len(candidates) >= 4:
            match_maker.srv.send_string('MATCH %s %s %s'%(match_maker.usr, match_maker.channel,
                                                          ' '.join(candidates[:4])))
            ans = match_maker.srv.recv_string()
            if ans.startswith('ERROR'):
                print(ans)
                exit()

        while list(filter(lambda p: p.poll() is None, CLIENTS)):
            time.sleep(5)
    except KeyboardInterrupt:
        pass
