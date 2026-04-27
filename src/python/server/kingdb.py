
import sys
import os
from pymongo import MongoClient

# Add common directory to path to find MONGODB.py
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'common')))

from MONGODB import *

def authenticate_player(name, password):
    try:
        client = MongoClient(MONGODB_CONNECTION_STRING)
        result = client.king.users.find_one({'name': name, 'password': password})
        if not result:
            # I'm not worried about real registration now, so if user does not exist, register!
            if client.king.users.find_one({'name': name}):
                return None # User already exists, which means password is wrong
            result = client.king.users.insert_one({
                'name': name, 'password': password
            })
            if not result or not result.inserted_id:
                return None # User registration failed, better abort
        return result
    except:
        print("MongoDB threw an exception, maybe connection couldn't be established. Proceed anyway, who cares.")
        return {'name': name, 'password': password}

def record_game(game_summary):
    client = MongoClient(MONGODB_CONNECTION_STRING)
    try:
        client.king.games.insert_one(game_summary)
    except:
        print("MongoDB threw an exception, maybe connection couldn't be established. Well, I guess game stats won't be recorded.")
