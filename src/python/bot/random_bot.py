#!/usr/bin/env python3

import sys
import os
import random

# Add client directory to path to find client.py
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'client')))

import client

class RandomPlayer(client.GamePlayer):
    def choose_game(self, choices):
        return random.choice(choices)

    def play_card(self):
        return random.choice(self.game.hand)

    def bid(self):
        # Select a random option with higher chance of forefeit (50%)
        possible_bids = 4 * [0] + 2 * [1] + 1 * [2] + 1 * [3]
        return random.choice(possible_bids)

    def decide(self):
        # Randomly accepts or refuses it
        return random.choice([True, False])

    def choose_trump(self):
        # Chooses some random suit if player won the bidding
        options = list("SCHD") + ['']
        return random.choice(options)

if __name__ == "__main__":
    usr = ''

    if len(sys.argv) < 3:
        print('Error, wrong usage.\n Usage: random_bot.py user password')

    usr = sys.argv[1]

    random.seed()
    client.run(usr, sys.argv[2], False, lambda: RandomPlayer())
