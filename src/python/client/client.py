"""
 Module client:
  Implements basic infrastructure for a client to the King game server
"""

import sys
import json
import zmq

class Server:
    def __init__(self, user_name):
        self.usr = user_name
        self.channel = ''
        self.game_fn = None
        self.accept_matches = False
        self.games = dict()
        self.user_list = []

        ### ZMQ Initialization ###
        ctx = zmq.Context()

        self.pubsrv = ctx.socket(zmq.SUB)
        self.pubsrv.connect('tcp://127.0.0.1:5556')

        self.srv = ctx.socket(zmq.REQ)
        self.srv.connect("tcp://127.0.0.1:5555")

    def authorize(self, pwd, game_create_fn, accept_matches=False):
        """ Authorize client with the server and setup game creation
            game_create_fn takes two parameters, this server and the table secret
                must return a game
            accept_matches is True if client accepts to join in new tables
        """
        self.srv.send_string('AUTHORIZE %s %s'%(self.usr, pwd))
        ans = self.srv.recv_string()
        if ans.startswith('ERROR'):
            return False

        # In case we have an old channel set in this client, unsubscribe to it
        if self.channel:
            self.pubsrv.setsockopt_string(zmq.UNSUBSCRIBE, self.channel)

        self.pubsrv.setsockopt_string(zmq.SUBSCRIBE, ans)
        self.channel = ans
        self.game_fn = game_create_fn
        self.accept_matches = accept_matches
        if accept_matches:
            self.pubsrv.setsockopt_string(zmq.SUBSCRIBE, 'user-list-channel')

        return True

    def get_user_list(self):
        msg = ''
        while not msg or msg.startswith('ERROR'):
            self.srv.send_string('LISTUSERS')
            msg = self.srv.recv_string()

        self.user_list = None
        while self.user_list is None:
            self.poll_sub(300)

        return self.user_list

    def poll_sub(self, timeout=1):
        if self.pubsrv.poll(timeout):
            topic, _, data = (self.pubsrv.recv_string()).partition(' ')

            if topic == 'user-list-channel':
                self.user_list = data.split(' ')
            elif self.channel and topic == self.channel:
                if self.game_fn and self.accept_matches:
                    if data.startswith('CONFIRM_AVAILABLE'):
                        self.srv.send_string('AVAILABLE %s %s'%(self.usr, self.channel))
                        self.srv.recv_string()
                    else:
                        self.join_table(data.split(' ')[1])
            else:
                game = self.games.get(topic)
                if game:
                    game.handle_msg(data)
                    if game.is_over:
                        self.games.pop(topic)

    def list_table(self):
        self.srv.send_string("LIST")
        return self.srv.recv_string()

    def create_table(self):
        self.srv.send_string("TABLE %s %s"%(self.usr, self.channel))
        return self.srv.recv_string()

    def join_table(self, name):
        self.pubsrv.setsockopt_string(zmq.SUBSCRIBE, name)
        self.srv.send_string("JOIN %s %s %s"%(self.usr, self.channel, name))
        ans = self.srv.recv_string()
        if ans.startswith('ERROR'):
            self.pubsrv.setsockopt_string(zmq.UNSUBSCRIBE, name)
            return False

        self.games[name] = self.game_fn(self, ans)
        return True

    def hunt_table(self):
        while True:
            msg = self.list_table()
            if msg.startswith('ERROR'):
                msg = '[]'

            tables = json.loads(msg)

            for table in filter(lambda t: len(t['players']) < 4, tables):
                if self.join_table(table['name']):
                    return True

            msg = self.create_table()
            if msg.startswith('ERROR'):
                return False

    def take_game_action(self, action, secret, *args):
        """ Used to send an action to a table """
        msg = "%s %s %s"%(action, self.usr, secret)
        if len(args):
            msg += ' %s'%(' '.join(args))

        self.srv.send_string(msg)
        return self.srv.recv_string()

class GamePlayer:
    """ Interface for Game Playing callbacks """
    game = None

    def set_game(self, game):
        """ Game is the current game state """
        self.game = game
        return self

    def choose_game(self, choices):
        """ Return one of the choices given """
        pass

    def bid(self):
        """ Callback to collect ammount player wants to bid """
        pass

    def inform_bid(self):
        """ Callback to inform last bid in the auction """
        pass

    def decide(self):
        """ Callback to get decision if player is the auctioner """
        pass

    def choose_trump(self):
        """ Callback to get trump suit if player won the bid (or is the auctioner and declined)"""
        pass

    def game_selected(self):
        """ Callback after game is set on the table """
        pass

    def play_card(self):
        """ Return one of the cards in self.game.hand (Plays that card) """
        pass

    def card_played(self):
        """ Callback after card is played on the table """
        pass

    def end_round(self, winner):
        """ Callback after round is ended, winner is player that wins the round """
        pass

    def end_hand(self):
        """ Callback after hand is over """
        pass

class Game:
    """ Keeps track of game information """
    def __init__(self, server, secret, game_player):
        self.hand = []
        self.players = []
        self.scores = []
        self.last_score = 0
        self.round = 0
        self.turn = ''
        self.table = []
        self.is_over = False
        self.game = ''
        self.bidder = ''
        self.max_bid = 0
        self.max_bidder = ''
        self.trump = ''

        self.handlers = {k[len('H_'):]:v for k, v in Game.__dict__.items() if k.startswith('H_')}
        self.server = server
        self.secret = secret
        self.player = game_player.set_game(self)

    def handle_msg(self, content):
        """ Invokes the handler for the message received """
        print("Handling ", content)
        content = content.split(' ')
        cmd = self.handlers.get(content[0], lambda *args: print("Invalid message"))
        cmd(self, *content[1:])

    def H_START(self, *players):
        """ Handles the start of a new game """
        self.players = list(players)

    def H_BID(self, bidder):
        """ Handles the bid turn """
        self.bidder = bidder
        if self.bidder == self.server.usr:
            msg = 'ERROR'
            while msg.startswith('ERROR'):
                msg = self.server.take_game_action('BID', self.secret, str(self.player.bid()))

    def H_BIDS(self, value):
        """ Handles the bidding value info """
        bid = int(value) # I can assume that server only inform valid bids
        if not self.max_bidder or bid:
            self.max_bid = bid
            self.max_bidder = self.bidder

        self.player.inform_bid()

    def H_DECIDE(self, player):
        """ Handles the auctioner decision """
        if player == self.server.usr:
            msg = 'ERROR'
            while msg.startswith('ERROR'):
                msg = self.server.take_game_action('DECIDE', self.secret, str(self.player.decide()))

    def H_CHOOSETRUMP(self, player):
        """ Handles the trump suit choice """
        if player == self.server.usr:
            msg = 'ERROR'
            while msg.startswith('ERROR'):
                msg = self.server.take_game_action('TRUMP', self.secret,\
                                                    self.player.choose_trump())

    def H_STARTHAND(self, start_player, *choices):
        """ Handles the start of a new hand """
        self.turn = start_player
        self.hand = json.loads(self.server.take_game_action('GETHAND', self.secret))
        self.max_bid = 0

        # Use choice function if its user's turn
        if self.server.usr == start_player:
            msg = 'ERROR'
            while msg.startswith('ERROR'):
                msg = self.server.take_game_action('GAME', self.secret,\
                                                   self.player.choose_game(list(choices)))

    def H_GAME(self, game, *trump):
        """ Handles the selection of a game for the hand """
        self.game = game
        self.trump = '' if not trump else trump[0]
        self.player.game_selected()

    def H_TURN(self, player):
        """ Handles the Turn information """
        self.turn = player
        if self.server.usr == player:
            msg = 'ERROR'
            card = ''
            while msg.startswith('ERROR'):
                card = self.player.play_card()
                msg = self.server.take_game_action('PLAY', self.secret, card)

            self.hand.remove(card)

    def H_PLAY(self, card):
        """ Handles the Card playing information """
        self.table.append((self.turn, card))
        self.player.card_played()

    def H_ENDROUND(self, winner, score):
        """ Handles the end of a round """
        self.table.clear()
        self.last_score = int(score)
        self.player.end_round(winner)

    def H_ENDHAND(self, *score):
        """ Handles the end of a round """
        self.scores.append(list(score))
        self.player.end_hand()

    def H_GAMEOVER(self, *score):
        """ Handles the end of the game """
        self.is_over = True


def run(user, passwd, accept_matches=False, player_creation_fn=lambda: GamePlayer()):
    """ Helper function that establishes a table and run the game loop  """
    srv = Server(user)
    if not srv.authorize(passwd, lambda s, n: Game(s, n, player_creation_fn()), accept_matches):
        # Failure authorizing user
        return False

    if not accept_matches and not srv.hunt_table():
        return False

    while accept_matches or len(srv.games):
        srv.poll_sub()

    return True

if __name__ == "__main__":
    usr = ''
    password = ''

    if len(sys.argv) > 2:
        usr = sys.argv[1]
        password = sys.argv[2]

    run(usr, password)
