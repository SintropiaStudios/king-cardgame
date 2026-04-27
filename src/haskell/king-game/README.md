# King Server and Client in Haskell

King is a card game that I learned and used to play while in College, but very few people know about it or care for a match, so I built my own using a Python Server and ZeroMQ. I have already a working Python Client and a browser version with NodeJS making the bridge with ZeroMQ using WebSockets for duplex communication with browser.

The original purpose of this Client is less to offer a CLI/GUI for playing the game, but rather to have a client available for either building those or, as done in Python, have a Bot made using it so I can play against.

The server provides an alternative option, probably more reliable and testable.

Info on the game can be found in my blog http://elloxas.blogspot.com (in Portuguese) and I have a running (sometimes) version in http://king.epensieve.com:8086
