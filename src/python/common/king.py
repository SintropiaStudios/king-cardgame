# -*- coding: utf-8 -*-
from random import shuffle
from functools import reduce
from enum import Enum
from operator import itemgetter

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']

class BaseGame:
    """ This class has the basic rule of the game (Trick tacking),
    and the basic table evaluation when the round ends
    All games derive from this class
    """

    def __init__(self):
        self.round = 0
        self.score = 1

    def is_last_round(self):
        """Check for a final round"""
        return self.round == 13

    def play_round(self, table, pivot_index=0):
        """Check the round and increment it
        @param table must have 4 entries and each entry is terminated with its suit
        @return the pair position of table winner and score"""
        self.round += 1
        table = list(map(lambda x: (RANKS.index(x[:-1]), x[-1]), table))
        pivot = table[pivot_index]
        return (table.index(max(filter(lambda x: x[-1] == pivot[-1],
                                       table))), self.score)

    def hand_constraint(self, table, hand, play):
        """Player must play one card of the same suit that started the table
        @param table is the current table state
        @param hand is the player hand
        @param play is the card player has chose"""
        if not play in hand:
            return False

        if not len(table):
            return True

        possible = list(filter(lambda x: x[-1] == table[0][-1], hand))
        return (not len(possible)) or (possible.count(play))

class Vaza(BaseGame):
    """ English No Tricks
    Just like the base game, but score is -20 each round you make
    """

    def __init__(self):
        BaseGame.__init__(self)
        self.score = -20

class DuasUltimas(BaseGame):
    """English No Last 2 Tricks
    Just like the base game, but last 2 rounds worth -90 points each
    """

    def __init__(self):
        BaseGame.__init__(self)
        self.score = 0

    def play_round(self, table):
        """As BaseGame increments round later, last rounds are 11 and 12"""
        if self.round > 10:
            self.score = -90
        return BaseGame.play_round(self, table)

class Mulheres(BaseGame):
    """ English No Queens
        Just like the base game, but each queen in table is worth -50 """

    def __init__(self):
        BaseGame.__init__(self)
        self.score = 0

    def play_round(self, table):
        """ Count the number of woman cards in table (Queens),
            each one is worth -50 points """
        self.score = -50 * len(list(filter(lambda x: x[0] == 'Q', table)))
        return BaseGame.play_round(self, table)

class Homens(BaseGame):
    """ English No Kings or Jacks
        Just like the base game, but each king or jack in table is worth -30 """
    def __init__(self):
        BaseGame.__init__(self)
        self.score = 0

    def play_round(self, table):
        """ Count the number of man cards in table (Kings and Jacks),
            each one is worth -30 points """
        self.score = -30 * len(list(filter(lambda x: x[0] in ['K', 'J'], table)))
        return BaseGame.play_round(self, table)

class Copas(BaseGame):
    """ English No Hearts
        Just like the base game, but each card with hearts suit is worth -20
        Also you cannot start with Hearts unless you only have Hearts """
    def __init__(self):
        BaseGame.__init__(self)
        self.score = 0

    def play_round(self, table):
        """ Count the number of hearts suit cards in table,
            each one is worth -20 points """
        self.score = -20 * len(list(filter(lambda x: x[-1] == 'H', table)))
        return BaseGame.play_round(self, table)

    def hand_constraint(self, table, hand, play):
        """ Player cannot play Hearts unless he only have Hearts
            or table started with Hearts """
        if not play in hand:
            return False

        if not len(table) and play[-1] == 'H':
            return not len(list(filter(lambda x: x[-1] != 'H', hand)))
        return BaseGame.hand_constraint(self, table, hand, play)

class King(BaseGame):
    """ English No King of Hearts
        Same hand constraint of No Hearts, but King of Hearts ends the hand and
        is worth -160 points """
    def __init__(self):
        BaseGame.__init__(self)
        self.score = 0
        self.kingOfHearts = False

    def is_last_round(self):
        """ Helper to detect if it's the last round """
        return self.kingOfHearts or self.round == 13

    def play_round(self, table):
        """ Check for the King of Hearts, whoever wins a round with it takes -160 """
        self.score = -160 * table.count('KH')
        self.kingOfHearts = (self.score == -160)
        return BaseGame.play_round(self, table)

    def hand_constraint(self, table, hand, play):
        """ Player cannot play Hearts unless he only have Hearts
                or table started with Hearts
            If Player has the King of Hearts and don't have the suit on table,
                HE MUST DISCARD THE KING OF HEARTS """
        if not play in hand:
            return False

        if not len(table):
            return play[-1] != 'H' or \
                not len(list(filter(lambda x: x[-1] != 'H', hand)))

        possible = list(filter(lambda x: x[-1] == table[0][-1], hand))
        if not len(possible):
            return play == 'KH' or not hand.count('KH')

        return possible.count(play)

class Positiva(BaseGame):
    """ English Positives
        Just like the base game, where each round score 25
        In adition we have:
         - Trump Suit: Even when discarded, this suit takes the round """

    def __init__(self, trump=''):
        BaseGame.__init__(self)
        self.trump = trump
        self.score = 25

    # Check for Trump Suit and if found use it index for pivot suit
    def play_round(self, table):
        elem = list(filter(lambda x: x[-1] == self.trump, table))
        index = table.index(elem[0]) if elem else 0
        return BaseGame.play_round(self, table, index)

    def __str__(self):
        return 'POSITIVA'


_HANDS = \
    {
        'VAZA': Vaza,
        '2ULTIMAS': DuasUltimas,
        'MULHERES': Mulheres,
        'HOMENS': Homens,
        'COPAS': Copas,
        'KING': King,
        'POSITIVA': Positiva
    }


class KingPlayer:
    """ Simple class to store player information
        Mainly store players hand and list of chosen hands """

    def __init__(self, name, secret):
        self.name = name
        self.secret = secret
        self.hand = []
        self.games = []

    def set_hand(self, hand):
        self.hand = sorted(hand, key=lambda c: (c[1], RANKS.index(c[0])))
        return self

    def add_game(self, game):
        self.games.append(game)

    def card_in_hand(self, card):
        """ Test if the card played is in the players hand """
        return card in self.hand

    def __eq__(self, other):
        if isinstance(other, KingPlayer):
            return self.name == other.name and self.secret == other.secret
        return False

    def __hash__(self):
        return hash((self.name, self.secret))

    def __str__(self):
        return self.name

class GameState(Enum):
    NOT_STARTED = 1
    CHOOSE_HAND = 2
    BIDDING = 3
    DECIDE_BID = 4
    CHOOSE_TRUMP = 5
    RUNNING = 6
    ROUND_OVER = 7
    HAND_OVER = 8
    GAME_OVER = 9

class KingTable:
    """ Class to control the game flow for a full game of King
        The game takes 10 hands, each hand with 13 cards per player
        and a set of rules, that I'm calling the game """

    def __init__(self, name):
        self.name = name
        self.players = []
        self.score = []
        self.game = None
        self.state = GameState.NOT_STARTED
        self.table = []
        self.turn = 0
        self.bids = []
        self.bid_turn = 0

    def get_player(self, player):
        for p in self.players:
            if p == player:
                return p
        return None

    def join_table(self, player):
        if len(self.players) == 4:
            return False

        self.players.append(player)
        return True

    def num_players(self):
        return len(self.players)

    def possible_hands(self, player):
        games = list(_HANDS.keys())
        for p in self.players:
            played = filter(lambda x: p == player or
                            x != 'POSITIVA', p.games)
            for c in played:
                games.remove(c)
        return games or ['POSITIVA']

    def start(self):
        if len(self.players) == 4:
            shuffle(self.players)
            return True

        return False

    def setup_hand(self):
        """ Sets up a new hand but doesn't start it as a game must be chosen """
        deck = [x + y for x in RANKS for y in ['S', 'C', 'H', 'D']]
        shuffle(deck)

        start, stop = 0, 13
        for player in self.players:
            player.set_hand(deck[start:stop])
            start, stop = stop, stop + 13

        self.state = GameState.CHOOSE_HAND
        self.turn = len(self.score) % 4
        return self.players[self.turn]

    def start_positiva(self, player):
        """ If allowed, starts the Biding process before a game is chosen """
        if self.state is not GameState.CHOOSE_HAND or \
           player not in self.players or \
           self.players[self.turn] != player or \
           str(Positiva()) not in self.possible_hands(player):
            return False

        self.state = GameState.BIDDING
        self.bid_turn = (self.turn + 1) % 4
        self.bids = [0] * 4

        return True

    def bid(self, player, ammount):
        """ Handles the player's bids """
        if self.state is not GameState.BIDDING or \
           player not in self.players or \
           self.players[self.bid_turn] != player or \
           self.players[self.turn] == player:
            return False

        if ammount != 0 and \
           not max(self.bids) < ammount < 13:
            return False

        # An ammount of 0 means forefeit, we store as -1 to
        # differentiate from those that haven't bid
        self.bids[self.bid_turn] = ammount if ammount > 0 else -1

        # Finds the next bidder
        while self.bid_turn != self.turn:
            self.bid_turn = (self.bid_turn + 1) % 4
            if self.bids[self.bid_turn] >= 0:
                break

        if self.bid_turn == self.turn:
            # Check to see if it's time to decide
            if self.bids.count(-1) >= 2:
                # The auctioner always bids 0, if 2 more players forefeit is time to decide
                # If all bidders forefeit, there is no choice to make, skip to trump choosing
                self.state = GameState.DECIDE_BID if self.bids.count(-1) < 3 \
                        else GameState.CHOOSE_TRUMP
            else:
                # In case there is at least two bidders, go back to lowest offer
                self.bid_turn = min(filter(lambda x: x[1] > 0, \
                                    enumerate(self.bids)), key=itemgetter(1))[0]

        return True

    def decide(self, player, decision):
        """ Handles the decision to accept or not the bid, returns the winner bid """
        if self.state is not GameState.DECIDE_BID or \
           player not in self.players or \
           self.players[self.turn] != player:
            return ''

        # decision is a boolean representing acceptance of the winning bid
        if not decision:
            # Forefeit all bids if auctioner has not accepted except the auctioner
            self.bids = 4 * [-1]
            self.bids[self.turn] = 0

        self.state = GameState.CHOOSE_TRUMP

        # Return name of bid winner (it can be the auctioner if he declines)
        self.bid_turn = max(enumerate(self.bids), key=itemgetter(1))[0]
        return self.players[self.bid_turn].name

    def choose_trump(self, player, *trump):
        """ Handles the choice of a trump suit """
        if self.state is not GameState.CHOOSE_TRUMP or \
           player not in self.players or \
           player != self.players[self.bid_turn]:
            return False

        self.state = GameState.CHOOSE_HAND
        res = self.start_hand(self.players[self.turn], str(Positiva()), *trump)
        if not res:
            self.state = GameState.CHOOSE_TRUMP

        return res

    def start_hand(self, player, game, *trampling):
        """ Starts a new hand, with player being the starter and
        game a valid option in HANDS, if game is POSITIVA then
        trampling will indicate a trampling suit"""

        if self.state is not GameState.CHOOSE_HAND or \
           player not in self.players or \
           self.players[self.turn] != player or \
           game not in self.possible_hands(player) or \
           (trampling and trampling[0] not in ['S', 'H', 'C', 'D']):
            return False

        # Positives could come with Trump Suit
        # Start the game
        self.game = _HANDS[game]() if not trampling else \
                    _HANDS[game](trampling[0])

        self.score.append(4 * [0])
        self.state = GameState.RUNNING

        player.add_game(game)

        return True

    def play_card(self, player, card):
        """ Handles card playing """
        if self.state is not GameState.RUNNING or \
           player not in self.players or \
           self.players[self.turn] != player or \
           not self.game.hand_constraint(self.table, player.hand, card):
            return False

        self.table.append(card)
        player.hand.remove(card)
        self.turn = (self.turn + 1) % 4

        if len(self.table) == 4:
            self.state = GameState.ROUND_OVER

        return True

    def end_round(self):
        """ Handles end of the round """
        if self.state is not GameState.ROUND_OVER:
            return (None, None)

        (winner, pts) = self.game.play_round(self.table)

        self.turn = (self.turn + winner) % 4
        self.table = []
        self.score[-1][self.turn] += pts

        if self.game.is_last_round():
            self.state = GameState.HAND_OVER
        else:
            self.state = GameState.RUNNING

        return (self.players[self.turn], pts)

    def end_hand(self):
        """ Handles end of the hand """
        if self.state is not GameState.HAND_OVER:
            return False

        if isinstance(self.game, Positiva) and self.bid_turn != self.turn:
            # Fix score based on bids placed
            # TODO Decide what rule to apply if bid winner doesn't have enough pts
            self.score[-1][self.bid_turn] -= self.bids[self.bid_turn] * 25 # Each bid is 25 poits
            self.score[-1][self.turn] += self.bids[self.bid_turn] * 25

        self.state = GameState.CHOOSE_HAND if len(self.score) < 10 else GameState.GAME_OVER
        return True

    def end_game(self):
        """ Checks for end of game """
        return self.state is GameState.GAME_OVER

    def get_score(self):
        """ Return Game Score """
        return reduce(lambda a, b: map(lambda x, y: x + y, a, b), self.score, 4 * [0])


if __name__ == "__main__":

    print("Testing game evaluation: Vaza")
    assert Vaza().play_round(['2H', '5H', 'AS', '4H']) == (1, -25)
    assert Vaza().play_round(['TD', '5C', 'AS', '4H']) == (0, -25)
    assert Vaza().play_round(['3C', '3H', 'AC', '4H']) == (2, -25)
    assert Vaza().play_round(['5S', '6S', 'KS', 'AS']) == (3, -25)

    print("Testing game evaluation: Duas Ultimas")
    assert DuasUltimas().play_round(['5H', 'KS', 'AC', 'TH']) == (3, 0)
    DU = DuasUltimas()
    DU.round = 11
    assert DU.play_round(['5H', 'QS', 'JS', '2H']) == (0, -90)
    assert DU.play_round(['TC', 'QS', 'QC', '5H']) == (2, -90)

    print("Testing game evaluation: Mulheres")
    assert Mulheres().play_round(['5H', 'KS', 'AC', 'TH']) == (3, 0)
    assert Mulheres().play_round(['5H', 'QS', 'JS', '2H']) == (0, -50)
    assert Mulheres().play_round(['TC', 'QS', 'QC', '5H']) == (2, -100)
    assert Mulheres().play_round(['2H', 'QH', 'QC', 'QD']) == (1, -150)
    assert Mulheres().play_round(['QD', 'QS', 'QC', 'QH']) == (0, -200)

    print("Testing game evaluation: Homens")
    assert Homens().play_round(['5H', 'AS', 'AC', 'TH']) == (3, 0)
    assert Homens().play_round(['5H', 'QS', 'JS', '2H']) == (0, -30)
    assert Homens().play_round(['TC', 'KS', 'JC', '5H']) == (2, -60)
    assert Homens().play_round(['2H', 'KH', 'JH', 'KD']) == (1, -90)
    assert Homens().play_round(['KD', 'JS', 'KC', 'JD']) == (0, -120)

    print("Testing game evaluation: Copas")
    assert Copas().play_round(['5H', 'AS', 'AC', 'TH']) == (3, -40)
    assert Copas().play_round(['5D', '6H', 'AD', 'TC']) == (2, -20)
    assert Copas().play_round(['5H', 'TH', 'AD', '2H']) == (1, -60)
    assert Copas().play_round(['AH', '6H', 'KH', 'TH']) == (0, -80)
    assert Copas().play_round(['5D', '6S', 'AD', 'TC']) == (2, 0)

    print("Testing game evaluation: King")
    k = King()
    assert King().play_round(['5H', 'AS', 'AC', 'TH']) == (3, 0)
    assert not k.is_last_round()
    k = King()
    assert k.play_round(['AH', '6C', 'KH', 'TH']) == (0, -160)
    assert k.is_last_round()

    print("Testing game evaluation: Positiva")
    assert Positiva().play_round(
        ['5H', 'AS', 'AC', 'TH']) == (3, 25)  # no trump
    assert Positiva('H').play_round(
        ['5D', '6H', 'AD', 'TD']) == (1, 25)  # hearts
    assert Positiva('C').play_round(
        ['5H', 'TH', '2C', '2D']) == (2, 25)  # clubs
    assert Positiva('D').play_round(
        ['AD', '6D', 'KD', 'TD']) == (0, 25)  # diamonds
    assert Positiva('S').play_round(
        ['5D', '6S', 'AH', 'TC']) == (1, 25)  # spades
    # trump but no trump
    assert Positiva('H').play_round(['5C', '2S', 'AC', 'TC']) == (2, 25)

    print("Testing simple hand constraint")
    assert BaseGame().hand_constraint([], ['2C', '3H'], '3H')  # empty hand
    # play the table naipe
    assert BaseGame().hand_constraint(['2C'], ['2H', '3C'], '3C')
    assert not BaseGame().hand_constraint(
        ['2C'], ['2H', '3C'], '2H')  # invalid play
    # more than one option
    assert BaseGame().hand_constraint(
        ['2C'], ['2H', '3C', '5C', 'AS', 'AC'], '5C')
    assert BaseGame().hand_constraint(
        ['AD', 'JD', 'QH'], ['2C', '3C'], '2C')  # discard

    print("Testing game hand constraint: Copas")
    assert Copas().hand_constraint([], ['2C', '3H'], '2C')  # empty table
    assert not Copas().hand_constraint([], ['2C', '3H'], '3H')  # wrong start
    assert Copas().hand_constraint(['2H'], ['2C', '3H'], '3H')  # play the suit
    # burn on discard
    assert Copas().hand_constraint(['2C'], ['2H', '3H'], '3H')

    print("Testing game hand constraint King")
    assert King().hand_constraint([], ['2C', 'KH'], '2C')  # empty table
    assert not King().hand_constraint([], ['2C', 'KH'], 'KH')  # wrong start
    assert King().hand_constraint(['2H'], ['3H', 'KH'], '3H')  # play the suit
    assert King().hand_constraint(['2C'], ['2H', 'KH', '3D'], 'KH')  # must discard

    print("Testing playing cards in your hand")
    assert KingPlayer('t', None).set_hand(['2C', '4H']).card_in_hand('4H')
    assert not KingPlayer('t', None).set_hand(['3C', '5D']).card_in_hand('8S')
    assert KingPlayer('t', None).set_hand(['5H', '6S', '8D']).card_in_hand('6S')

    print("Checking for Hand Instances")
    assert isinstance(_HANDS['COPAS'](), Copas)

    print("Checking Possible Hands")
    k = KingTable('')
    for i in range(4):
        k.join_table(KingPlayer(str(i), ''))

    VALID = list(_HANDS.keys())
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('COPAS')))
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('KING')))
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('2ULTIMAS')))
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('POSITIVA')))
    assert k.possible_hands(k.players[0]) == VALID
    assert k.possible_hands(k.players[0]).count('POSITIVA') == 0
    k.players[0].games.append(VALID.pop(VALID.index('HOMENS')))
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('MULHERES')))
    assert k.possible_hands(k.players[0]) == VALID
    k.players[0].games.append(VALID.pop(VALID.index('VAZA')))
    assert k.possible_hands(k.players[0]).count('POSITIVA') == 1

    print("Checking Positiva Biding")
    k = KingTable('')
    for i in range(4):
        k.join_table(KingPlayer(str(i), ''))

