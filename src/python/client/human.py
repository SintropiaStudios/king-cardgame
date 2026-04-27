#!/usr/bin/env python3
"""
    Console client for the King Game
"""
import sys
import os
import time

# Ensure the client directory is in the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import client

USR_NAME = ''
CLR_CMD = 'cls' if sys.platform == 'win32' else 'clear'

def clear_screen():
    _ = os.system(CLR_CMD)

def print_hand(player):
    print("Your Hand:", player.game.hand, "\n")

class HumanPlayer(client.GamePlayer):
    """ Implements a Console based human player """
    def choose_game(self, choices):
        clear_screen()
        print("A new hand is about to start, you must choose a game.")
        print_hand(self)
        print("Your choices:", choices, "\n")
        choice = ''
        while not choice:
            res = input('>')
            choice = res if res in choices else ''

        return choice

    def bid(self):
        print_hand(self)
        print("You have a chance to bid, inform value:")
        bid = -1
        while bid < 0:
            try:
                bid = int(input('>'))
            except ValueError:
                pass

        return bid

    def inform_bid(self):
        name = self.game.max_bidder if self.game.max_bidder != USR_NAME else 'You'
        #TODO if bid was 0, then it means forefeiting
        print(name, "bid", self.game.max_bid)
        time.sleep(2)

    def decide(self):
        print("Time for you to decide, do you accept ", self.game.max_bidder, \
              " bid of ", self.game.max_bid, "? (y/N)")
        return input('>').lower() == 'y'

    def choose_trump(self):
        if self.game.turn != USR_NAME:
            print("You win the auction with a bid of ", self.game.max_bid)
        print("Choose a trump suit (S, H, D, C) or empty for no trump:")
        res = 'I'
        while res and res not in "SHDC":
            res = input('>').capitalize()

        return res

    def game_selected(self):
        clear_screen()
        print("A new hand started. The game will be", self.game.game)
        if self.game.trump:
            print("Trump suit is ", self.game.trump)
        time.sleep(2)

    def play_card(self):
        clear_screen()
        print("It's your turn, choose card. (Game is %s)\n"%(self.game.game))
        if self.game.trump:
            print("Trump suit is ", self.game.trump)

        print("Your Hand:", list(enumerate(self.game.hand)), "\n")
        print("Table is:", self.game.table)
        card = ''
        while not card:
            res = input('>').capitalize()
            try:
                res = self.game.hand[int(res)]
            except (ValueError, IndexError):
                pass

            card = res if res in self.game.hand else ''

        return card

    def card_played(self):
        name = self.game.turn if self.game.turn != USR_NAME else 'You'
        print(name, "played", self.game.table[-1])
        print("Table now is: ", self.game.table)
        time.sleep(2)

    def end_round(self, winner):
        name, verb = (winner, "takes") if winner != USR_NAME else ('You', 'took')
        print(name, verb, "the round")
        time.sleep(4)
        clear_screen()

    def end_hand(self):
        time.sleep(1)
        clear_screen()

if __name__ == "__main__":

    if len(sys.argv) < 3:
        print('Wrong usage: human.py USER PASSWORD')
    USR_NAME = sys.argv[1]

    client.run(USR_NAME, sys.argv[2], False, lambda: HumanPlayer())
    