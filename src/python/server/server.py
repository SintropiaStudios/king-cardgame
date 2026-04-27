#!/usr/bin/env python3

import atexit
import json
import uuid
import threading
import zmq
import sys
import os
from datetime import datetime

# Add common directory to path to find king.py
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'common')))

from kingdb import *
from king import *

g_tables = dict()
g_players = dict()
g_users = dict()


class User:
    def __init__(self, name, channel = ''):
        self.name = name
        self.channel = channel
        self.players = dict()
        self.authorized = False
        self.is_bot = False

    def authorize(self, password):
        """ Authorizes a user an return a channel """
        if not self.authorized and authenticate_player(self.name, password):
            self.authorized = True
            self.channel = str(uuid.uuid4())

        return self.channel

    def __hash__(self):
        return hash((self.name, self.channel))

    def __eq__(self, other):
        return isinstance(other, User) and hash(self) == hash(other)

    def add_player(self, player, table_name):
        self.players[table_name] = player

    def remove_player(self, table_name):
        self.players.pop(table_name, None)

def flatten(l):
    return [item for sublist in l for item in sublist]

def pool_req(handler_map, timeout=1000):
    """Pool Request handler, just to keep it of with game logic"""
    socks = poller.poll(timeout)
    if not len(socks):
        return False

    msg = action_server.recv_string()
    print('received: %s'%msg)

    msg = msg.split(' ')
    cmd = handler_map.get(msg[0], lambda _: 'ERROR: Invalid Message')
    try:
        action_server.send_string(cmd(*msg[1:]))
    except TypeError:
        action_server.send_string('ERROR Invalid Call')

    return True

def create_table(usr_name, channel):
    """Manager Logic: TABLE - Creates a new table with the given parameters"""
    user = g_users.get(usr_name, None)
    if not user or user.channel != channel:
        return 'ERROR User not authorized'

    table_name = str(uuid.uuid4())

    g_tables[table_name] = KingTable(table_name)
    return table_name

def close_table(table_name, reason='game over'):
    """ Helper function for table removal """
    # Remove table from tables and capture its score
    table = g_tables.pop(table_name)
    score = table.get_score()

    # Notify all players that game is over
    status_publisher.send_string('%s GAMEOVER %s'%(table.name, ' '.join(map(str, score))))

    # Save table on DB (I'm not capturing the result because there is no recovery from failure here)
    record_game({
        'name': table.name,
        'players': [str(p) for p in table.players],
        'hand_scores': [{
            'game': table.players[turn_score[0]%4].games[turn_score[0]//4],
            'score': turn_score[1]
        } for turn_score in enumerate(table.score)],
        'final_score': [s for s in table.get_score()],
        'date': datetime.utcnow()
    })

    for player in table.players:
        # Remove players from quick access dict
        g_players.pop(player, None)

        # Remove player from owner user's list
        g_users[player.name].players.pop(table_name)

def list_tables():
    """Manager Logic: LIST - List all available tables"""
    return json.dumps([{'name': t[0], 'players':[str(p) for p in t[1].players]}\
                         for t in g_tables.items()])

def leave_table(usr_name, secret):
    """Game Logic: LEAVE - Used to remove players from a table"""
    player = KingPlayer(usr_name, secret)
    table = g_players.pop(player, None)

    # Remove player from table and abort if it was running
    if table:
        # Send a message notifying players leaving table
        status_publisher.send_string('%s LEAVE %s'%(table.name, player.name))

        if table.state is GameState.NOT_STARTED:
            table.players.remove(player)
            g_users[player.name].players.pop(table.name)
        else:
            close_table(table.name)
    else:
        return 'ERROR Player not in table'

    return 'ACK'

def join_table(usr_name, channel, table_name):
    """Game Logic: JOIN - Used to add new players to an existing table"""
    user = g_users.get(usr_name)
    if not user or user.channel != channel:
        return 'ERROR User not authorized'

    if table_name in user.players:
        return 'ERROR User already in table'

    player = KingPlayer(usr_name, str(uuid.uuid4()))

    table = g_tables.get(table_name, None)
    if not table:
        return 'ERROR Table does not exist'

    if not table.join_table(player):
        return 'ERROR Table is already full'

    # Quick access to game from player's info
    g_players[player] = table
    user.add_player(player, table_name)

    t = threading.Timer(1.0, inform_table_start, [table, table_name])
    t.start()

    return player.secret

def inform_table_start(table, table_name):
    # If game ready to start, handles main protocol
    if table.start():
        # Send message for players signaling game start, send also players list
        status_publisher.send_string('%s START %s'%(table_name, \
                                                    ' '.join([s.name for s in table.players])))
        # Send info regarding the start of a hand
        start_hand(table)

def start_hand(table):
    """ Messages used in hand start """
    # Distribute cards and inform players the starter and avilable game choices
    starter = table.setup_hand()
    choices = table.possible_hands(starter)
    status_publisher.send_string('%s STARTHAND %s %s'%(table.name, \
                                 starter.name, ' '.join(choices)))

def get_hand(usr_name, secret):
    """Game Logic: GetHand - Used to get a players hand"""
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    return json.dumps(table.get_player(player).hand)

def get_turn(usr_name, secret):
    """Game Logic: GetTurn - Used to get whose turn this is"""
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    return table.players[table.turn].name

def inform_turn(table):
    """Game Logic: Inform Turn is a helper function used to notify player's who's in the clock"""
    status_publisher.send_string('%s TURN %s'%(table.name, table.players[table.turn].name))

def choose_game(usr_name, secret, game):
    """Game Logic: ChooseGame - Used to choose the game for the current hand"""
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    # Positivas start a biding process
    if game == str(Positiva()) and table.start_positiva(player):
        status_publisher.send_string('%s BID %s'%(table.name, table.players[table.bid_turn].name))
        return 'ACK'

    if not table.start_hand(table.get_player(player), game):
        return 'ERROR Invalid action'

    # Inform players the chosen game
    status_publisher.send_string('%s GAME %s'%(table.name, game))

    # Inform the Turn
    inform_turn(table)

    return 'ACK'

def get_bid(usr_name, secret, value):
    """ Game Logic: Bid - Handles player bid """
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    try:
        if not table.bid(player, int(value)):
            raise ValueError
    except ValueError:
        return 'ERROR Invalid Action'

    status_publisher.send_string('%s BIDS %s'%(table.name, value))

    # Check for decision time
    if table.state is GameState.DECIDE_BID:
        status_publisher.send_string('%s DECIDE %s'%(table.name, table.players[table.turn].name))
    elif table.state is GameState.CHOOSE_TRUMP:
        status_publisher.send_string('%s CHOOSETRUMP %s'%(table.name, \
                                                            table.players[table.turn].name))
    else:
        status_publisher.send_string('%s BID %s'%(table.name, table.players[table.bid_turn].name))

    return 'ACK'

def get_decision(usr_name, secret, decision):
    """ Game Logic: Decide - Handles decision to take or not the winning bid """
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    bid_winner = table.decide(player, decision == 'True')
    if not bid_winner:
        return 'ERROR Invalid Action'

    status_publisher.send_string('%s CHOOSETRUMP %s'%(table.name, bid_winner))

    return 'ACK'

def get_trump(usr_name, secret, *trump):
    """ Game Logic: Trump - Handles the choice of a trump suit for the positive """
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    if not table.choose_trump(player, trump[0] if trump else ''):
        return 'ERROR Invalid action'

    # Inform players the chosen game
    game_str = '%s GAME %s'%(table.name, str(Positiva()))
    if trump:
        game_str += ' %s'%(trump[0])
    status_publisher.send_string(game_str)

    # Inform the Turn
    inform_turn(table)

    return 'ACK'


def play_card(usr_name, secret, card):
    """Game Logic: PlayCard - Handles logic for card playing and turn management"""
    player = KingPlayer(usr_name, secret)
    table = g_players.get(player, None)

    if not table:
        return 'ERROR Invalid Player'

    if not table.play_card(table.get_player(player), card):
        return 'ERROR Invalid Action'

    # Inform players the card played
    status_publisher.send_string('%s PLAY %s'%(table.name, card))

    # Check for end of round
    rnd_winner, score = table.end_round()
    if rnd_winner:
        status_publisher.send_string('%s ENDROUND %s %d'%(table.name, rnd_winner.name, score))
        # Check for end of hand
        if table.end_hand():
            score = table.score[-1]
            status_publisher.send_string('%s ENDHAND %s'%(table.name, ' '.join(map(str, score))))
            # Check for a game over
            if table.end_game():
                # Close table and inform scores (Full Game Score)
                close_table(table.name)
            else:
                # Sets up new hand
                start_hand(table)

            return 'ACK'

    # If we got here, game is on and so we inform the turn
    inform_turn(table)

    return 'ACK'

def cleanup(_tables):
    """ Simple helper function for notifying users when server goes down """
    for tbl in _tables.values():
        status_publisher.send_string('%s GAMEOVER %s'%(tbl, ' '.join(map(str, tbl.get_score()))))

def auth_player(usr_name, password):
    """ Basic auth protocol - Authenticates a player returning a secret to be used """
    usr = g_users.get(usr_name, User(usr_name))
    channel = usr.authorize(password)
    if not channel:
        return 'ERROR User does not exist or password is invalid'

    g_users[usr_name] = usr

    return channel

class ActiveUsers:
    def __init__(self):
        self.list = []
        self.listing = None

    def run(self, fnOnEnd):
        if not self.is_listening():
            self.list.clear()
            self.listing = threading.Timer(10.0, fnOnEnd)
            self.listing.start()

    def is_listening(self):
        return self.listing and self.listing.is_alive()


ACTIVE_USERS = ActiveUsers()

def send_list():
    """ Sends back list after collecting available users """
    status_publisher.send_string('user-list-channel %s'%(' '.join(ACTIVE_USERS.list)))

def confirm_available(usr_name, channel):
    """ Basic user protocol - Confirms user is available to matches """
    if not ACTIVE_USERS.is_listening():
        return 'ERROR Timeout on response'

    user = g_users.get(usr_name, None)
    if not user or user.channel != channel:
        return 'ERROR User not authorized'

    ACTIVE_USERS.list.append(user.name)

    return 'ACK'

def list_users():
    """ Basic user protocol - List available players """
    if ACTIVE_USERS.is_listening():
        return 'ERROR Listing in progress'

    for usr in g_users.values():
        status_publisher.send_string('%s CONFIRM_AVAILABLE'%(usr.channel))

    ACTIVE_USERS.run(send_list)

    return 'ACK'

def make_match(usr_name, channel, *others):
    """ Make a match using players (others must have size 3) either users or bots """
    # The plan is to use only users that confirmed last availability
    usrs = []
    for other in filter(lambda o: o in ACTIVE_USERS.list, others):
        usr = g_users.get(other)
        if usr:
            usrs.append(usr)

    if len(usrs) not in range(3, 5):
        return 'ERROR You must inform 3 or 4 other valid players'

    table = create_table(usr_name, channel)
    if not table.startswith('ERROR'):
        for usr in usrs:
            status_publisher.send_string('%s ASKJOIN %s'%(usr.channel, table))

    return table

### ZMQ Initialization ###
PORT = 5555
ZMQ_REQREP_CONN = "tcp://127.0.0.1:%d"%PORT
ZMQ_PUBSUB_CONN = "tcp://127.0.0.1:%d"%(PORT+1)
ctx = zmq.Context() 

action_server = ctx.socket(zmq.REP)
action_server.bind(ZMQ_REQREP_CONN)

status_publisher = ctx.socket(zmq.PUB)
status_publisher.bind(ZMQ_PUBSUB_CONN)

poller = zmq.Poller()
poller.register(action_server, zmq.POLLIN)

#This is used to hold all possible options for handling
#   protocol messages
handlers = {
    'AUTHORIZE': auth_player,
    'AVAILABLE': confirm_available,
    'LISTUSERS': list_users,
    'MATCH': make_match,
    'JOIN': join_table,
    'LEAVE': leave_table,
    'TABLE': create_table,
    'LIST': list_tables,
    'GETHAND': get_hand,
    'GETTURN': get_turn,
    'GAME': choose_game,
    'BID': get_bid,
    'DECIDE': get_decision,
    'TRUMP': get_trump,
    'PLAY': play_card
}

atexit.register(cleanup, g_tables)

try:
    # Main Game Loop
    while True:
        # Wait a few for some message and do it all again
        pool_req(handlers, 10)
except KeyboardInterrupt:
    pass
