var AllTranslateChoices = {
    'pt-br': {
        '0': 'Desiste',
        '1': '1 Positiva',
        '2': '2 Positivas',
        '3': '3 Positivas',
        '4': '4 Positivas',
        '5': '5 Positivas',
        'C': 'Paus',
        'S': 'Espadas',
        'H': 'Copas',
        'D': 'Ouros',
        '': 'Sem Trunfo',
        'COPAS': 'Copas',
        'VAZA': 'Vaza', 
        'MULHERES': 'Mulheres',
        'POSITIVA': 'Positiva',
        'HOMENS': 'Homens',
        'KING': 'King',
        '2ULTIMAS': '2 Ultimas',
        'True': 'Sim, aceito.',
        'False': 'Não, eu escolho.'
    },
    'en': {
        '0': 'Forefeit',
        '1': '1 Trick',
        '2': '2 Tricks',
        '3': '3 Tricks',
        '4': '4 Tricks',
        '5': '5 Tricks',
        'C': 'Clubs',
        'S': 'Spades',
        'H': 'Hearts',
        'D': 'Diamonds',
        '': 'No Trump',
        'COPAS': 'No Hearts',
        'VAZA': 'No Tricks', 
        'MULHERES': 'No Queens',
        'POSITIVA': 'Positive',
        'HOMENS': 'No Jacks and Kings',
        'KING': 'No King of Hearts',
        '2ULTIMAS': 'No Last 2 Tricks',
        'True': 'Yes, I accept',
        'False': 'No, I will choose'
    }
};

var TranslateChoices = AllTranslateChoices['pt-br'];

var TranslatedMessages = {
    'pt-br' : {
        'new_hand' : ["Sua vez de escolher a Regra, qual o jogo?", "Estas são as opções disponíveis, clique na desejada."],
        'get_bid' : ["Sua vez de fazer um lance, quantas positivas?", "Nenhum lance foi feito ainda.", "Qual será a sua oferta?"],
        'get_decision' : ["Temos uma oferta final, você aceita?", (max_bidder, max) => `${max_bidder} ofereceu ${max} positivas pela escolha.`],
        'get_trump' : ["Você tem a escolha!", "Escolha um dos naipes como o naipe Trunfo."],
        'game_start' : "Iniciando a Partida",
        'hand_start' : (choice, trump) => `A regra para a mão será ${choice}${trump ? ' (' + trump + ')' : ''}`,
        'starter_msg': (starter) => `${starter} vai começar e escolher a regra.`,
        'round_win' : ["Você venceu esta rodada.", (winner) => `${winner} venceu esta rodada.`],
        'authorize' : "Usuário autenticado com sucesso.",
        'join_succ' : "Usuário juntou-se a uma mesa, esperando demais jogadores para iniciar partida.",
        'join_fail' : "Falha ao tentar juntar-se à mesa, possivelmente alguém chegou antes, tente novamente.",
        'you': 'Você',
        'passed': 'passou.',
        'offered': (val) => `ofereceu ${val}.`,
        'player_left': (player) => `${player} saiu da mesa. Partida encerrada.`,
        'hand_summary_title': 'Fim da Mão',
        'game_over_title': 'Fim de Jogo',
        'winner_is': (winner, score) => `${winner} venceu com ${score} pontos!`,
        'continue': 'Continuar',
        'back_to_lobby': 'Voltar ao Lobby',
        'rematch': 'Jogar Novamente'
    },
    'en' : {
        'new_hand' : ["New Hand, what's the game?", "These are the choices, click the one you want to play."],
        'get_bid' : ["You're the current man on, how much will you give?", "No bids have been placed yet.", "What is your bid?"],
        'get_decision' : ["We have a winning bid, do you take it?", (max_bidder, max) => `${max_bidder} offered ${max} tricks for the choice.`],
        'get_trump' : ["You've got the choice!", "Choose one of the suits as the trump suit."],
        'game_start' : "The game has started",
        'hand_start' : (choice, trump) => `The game for this hand is ${choice}${trump ? ' (' + trump + ')' : ''}`,
        'starter_msg': (starter) => `${starter} will start and choose the rule.`,
        'round_win' : ["You take the round.", (winner) => `${winner} takes the round.`],
        'authorize' : "User is now authorized",
        'join_succ' : "Successfully joined a table. Waiting players.",
        'join_fail' : "Failed to Join a Table, possibly due to concurrent player, try again.",
        'you': 'You',
        'passed': 'passed.',
        'offered': (val) => `offered ${val}.`,
        'player_left': (player) => `${player} left the table. Match over.`,
        'hand_summary_title': 'Hand Over',
        'game_over_title': 'Game Over',
        'winner_is': (winner, score) => `${winner} wins with ${score} points!`,
        'continue': 'Continue',
        'back_to_lobby': 'Back to Lobby',
        'rematch': 'Rematch'
    },
}

var TranslateMessage = TranslatedMessages['pt-br'];

function setLanguage(lang) {
    if (AllTranslateChoices[lang]) {
        TranslateChoices = AllTranslateChoices[lang];
    }
    if (TranslatedMessages[lang]) {
        TranslateMessage = TranslatedMessages[lang];
    }
}

var GameStates = {
    NOT_STARTED: "NOT STARTED",
    PENDING_GAME: "STARTED BUT NO GAME",
    RUNNING: "RUNNING",
    ROUND_ENDING: "ENDING THE ROUND",
    HAND_ENDING: "ENDING THE HAND",
    WAITING_GAME: "WAITING FOR GAME",
    WAITING_BID: "WAITING FOR A BID",
    WAITING_DECISION: "WAITING FOR DECISION",
    WAITING_TRUMP: "WAITING FOR TRUMP SUIT",
    WAITING_PLAY: "WAITING FOR PLAY",
    GAME_OVER: "GAME OVER"
};

var PlayerPosition = {
    BOTTOM: 0,
    RIGHT: 1,
    TOP: 2,
    LEFT: 3,
    CAPACITY: 4
};

function Game(user) {

    this.table = new Table(user);
    this.user = user;
    this.channel = '';
    this.secret = '';
    this.hand = new Hand(this);
    this.state = GameStates.NOT_STARTED;
    this.cur_game = '';
    this.turn = '';

    // Receives the command to play a card from player
    // Only plays if it's player's turn
    this.play = function(card) {
        if (this.state === GameStates.WAITING_PLAY) {
            this.sendAction('PLAY', card, function(msg){
                console.log('Played card ' + card + "\nAnswer: " + msg);
            });
        }
    };

    // Used to process all card playing on the table
    this.playCard = function(card) {
        var position = this.table.players[this.turn];
        if ( position === PlayerPosition.BOTTOM) {
            this.hand.playCard(card);
        }

        this.table.addCard(card);
    };

    // Show user what hand options are available and get the choice
    this.chooseGame = function(choices) {
        var msg = TranslateMessage['new_hand'];
        this.updateRuleDisplay('...');
        this.createChoiceBox( msg[0], msg[1], choices, 'GAME');
    };

    this.updateRuleDisplay = function(rule, trump) {
        var el = document.getElementById('current-rule-display');
        if (!el) return;
        
        if (rule === '...') {
            el.textContent = '...';
            return;
        }
        
        var ruleLabel = TranslateChoices[rule] || rule;
        var trumpLabel = trump ? (TranslateChoices[trump] || trump) : null;
        var text = trumpLabel ? `${ruleLabel} (${trumpLabel})` : ruleLabel;
        
        el.textContent = text;
    };

    // Helper function used to generate option UI to the user
    this.createChoiceBox = function(title, body, choices, action) {
        $('#choiceArea').remove();
        var e = $("<div id='choiceArea'></div>").appendTo($('body'));
        
        $("<div class='choice-header'></div>").appendTo(e).append(`<h2>${title}</h2>`);
        $("<div class='choice-body'></div>").appendTo(e).append(`<p>${body}</p>`);
        
        var btnContainer = $("<div class='choice-actions'></div>").appendTo(e);

        for (var i=0; i < choices.length; i++) {
            var choiceKey = choices[i];
            var label = TranslateChoices[choiceKey] || choiceKey;
            
            $('<button></button>')
                .text(label)
                .addClass('primary-btn')
                .on('click', function(game, choice){
                    return function(evt) {
                        game.sendAction(action, choice, function(msg) {
                            console.log(`${action} with ${choice} selected, answer: ${msg}`);
                            $('#choiceArea').remove();
                        });
                    };
                }(this, choiceKey))
                .appendTo(btnContainer);
        }

        e.addClass('active');
    }

    // Show user UI so he can select what is his bids
    this.getBid = function() {
        var choices = ['0']; //Forefeiting is always an option
        var max = Math.max(...this.table.bids);
        if (max === -1) {
            max = 0;
        }

        // I'm limiting the bids to 5 as more it's very unusual
        for (var i = max + 1; i < 6; i++) {
            choices.push(i.toString());
        }

        var msg = TranslateMessage['get_bid'];
        var story = "";
        
        if (this.table.bid_history && this.table.bid_history.length > 0) {
            var historyText = this.table.bid_history.map(function(h) {
                var pName = (h.player === this.user) ? TranslateMessage['you'] : h.player;
                if (h.bid === 0) return `${pName} ${TranslateMessage['passed']}`;
                return `${pName} ${TranslateMessage['offered'](h.bid)}`;
            }.bind(this)).join("<br/>");
            story = historyText + "<br/><br/><strong>" + msg[2] + "</strong>";
        } else {
            story = msg[1];
        }

        this.createChoiceBox(msg[0], story, choices, 'BID');
    };

    // Show user UI so he can decide if he accepts or not the winning bid
    this.getDecision = function() {
        // Find the max bid and max bidder
        var max = Math.max(...this.table.bids);

        if (max <= 0) {
            // No one made a bid. Auto-decline the decision so we can proceed directly to choosing Trump.
            this.sendAction('DECIDE', 'False', function(msg) {
                console.log('Auto-declined decision as there were no bids: ' + msg);
            });
            return;
        }

        var max_index = this.table.bids.indexOf(max);
        var max_bidder = Object.keys(this.table.players).find(key => this.table.players[key] === max_index) || 'Ninguém';
        
        var msg = TranslateMessage['get_decision'];
        this.createChoiceBox(msg[0], msg[1](max_bidder, max), ['True', 'False'], 'DECIDE');
    };

    // Show user UI so he can decide what is the trump suit
    this.getTrump = function() {
        //TODO: BUG ON No Trump choice, I need to find out what's up
        var choices = "CDHS".split('');
        choices.push('');
        
        var msg = TranslateMessage['get_trump'];
        this.createChoiceBox(msg[0], msg[1], choices, 'TRUMP');
    };

    // Generic function used to Send some action to server
    this.sendAction = function(action, params, fnResponse) {
        socket.once('response', fnResponse);
        var cmd = `${action} ${this.user} ${this.secret}`;
        if (params !== '') {
            cmd += ' ' + params;
        }
        socket.emit('action', cmd);
    };

    this.sync = function() {
        this.sendAction('SYNC', '', function(msg) {
            if (msg.startsWith('SYNC_DATA')) {
                var parts = msg.split(' | ');
                var players = parts[0].split(' ').slice(1);
                var phase = parts[1];
                var turnName = parts[2];
                var rule = parts[3];
                var scores = parts[4].split(' ');

                this.table.setPlayers(players);
                this.table.setTotalScores(scores); // Use correct method for totals
                
                this.turn = turnName;
                if (phase === 'WaitingForRule') {
                    this.updateRuleDisplay('...');
                    if (this.turn === this.user) {
                        this.state = GameStates.WAITING_GAME;
                        this.chooseGame(rule.split(' '));
                    } else {
                        this.state = GameStates.PENDING_GAME;
                        show_message(TranslateMessage['starter_msg'](this.turn));
                    }
                } else if (rule !== 'NONE') {
                    this.cur_game = rule;
                    // Try to parse trump if it's POSITIVA
                    var trump = rule.startsWith('POSITIVA') ? rule.slice(8) : null;
                    var baseRule = trump ? 'POSITIVA' : rule;
                    this.updateRuleDisplay(baseRule, trump);
                    
                    var ruleLabel = TranslateChoices[baseRule] || baseRule;
                    var trumpLabel = trump ? (TranslateChoices[trump] || trump) : null;
                    show_message(TranslateMessage['hand_start'](ruleLabel, trumpLabel));
                }

                if (this.turn === this.user && phase === 'PlayingTrick []') {
                    this.state = GameStates.WAITING_PLAY;
                } else if (phase.startsWith('Bidding')) {
                    if (this.turn === this.user) {
                        this.state = GameStates.WAITING_BID;
                        this.getBid();
                    } else {
                        this.state = GameStates.RUNNING;
                    }
                } else if (phase.startsWith('DecidingBid')) {
                    if (this.turn === this.user) {
                        this.state = GameStates.WAITING_DECISION;
                        this.getDecision();
                    }
                } else if (phase.startsWith('ChoosingTrump')) {
                    if (this.turn === this.user) {
                        this.state = GameStates.WAITING_TRUMP;
                        this.getTrump();
                    }
                } else {
                    this.state = GameStates.RUNNING;
                }
                
                // Request hand just in case
                this.sendAction('GETHAND', '', function(response) {
                    if (!response.startsWith('ERROR')) {
                        this.hand.setCards(JSON.parse(response));
                    }
                }.bind(this));
            }
        }.bind(this));
    };

    this.showHandSummary = function(scores) {
        var title = TranslateMessage['hand_summary_title'];
        var bodyHTML = "<table style='width:100%; text-align:center;'><tr><th>Player</th><th>Hand</th><th>Total</th></tr>";
        for (var name in this.table.players) {
            var pos = this.table.players[name];
            var value = parseInt(scores[(this.table.table_index + pos) % PlayerPosition.CAPACITY]);
            var newTotal = this.table.total_score[name] + value;
            bodyHTML += `<tr><td>${name}</td><td>${value}</td><td>${newTotal}</td></tr>`;
        }
        bodyHTML += "</table>";
        
        if (this.createAlertBox) {
            this.createAlertBox(title, bodyHTML, TranslateMessage['continue'], () => {
                this.table.endHand(scores);
                if (this.isGameOver) {
                    this.state = GameStates.GAME_OVER;
                    this.showGameOver(this.finalScores);
                } else if (this.state === GameStates.HAND_ENDING) {
                    // Only reset to RUNNING if a background message (like TURN or BID) 
                    // hasn't already moved us to a waiting state
                    this.state = GameStates.RUNNING;
                }
            });
        } else {
            this.table.endHand(scores);
            if (this.isGameOver) {
                this.state = GameStates.GAME_OVER;
                this.showGameOver(this.finalScores);
            } else if (this.state === GameStates.HAND_ENDING) {
                this.state = GameStates.RUNNING;
            }
        }
    };

    this.showGameOver = function(scores) {
        var title = TranslateMessage['game_over_title'];
        var maxScore = -Infinity;
        var winner = "";
        for (var name in this.table.players) {
            var pos = this.table.players[name];
            var value = parseInt(scores[(this.table.table_index + pos) % PlayerPosition.CAPACITY]);
            if (value > maxScore) {
                maxScore = value;
                winner = name;
            }
        }
        
        var bodyHTML = `<h3 style='color:#d4af37; margin-bottom:1rem;'>${TranslateMessage['winner_is'](winner, maxScore)}</h3>`;
        bodyHTML += "<table style='width:100%; text-align:center; margin-bottom:1rem;'><tr><th>Player</th><th>Final Score</th></tr>";
        for (var name in this.table.players) {
            var pos = this.table.players[name];
            var value = scores[(this.table.table_index + pos) % PlayerPosition.CAPACITY];
            bodyHTML += `<tr><td>${name}</td><td>${value}</td></tr>`;
        }
        bodyHTML += "</table>";

        if (this.createGameOverBox) {
            this.createGameOverBox(title, bodyHTML);
        }
    };

    this.isBlockingPhase = function() {
        return this.state === GameStates.ROUND_ENDING || this.state === GameStates.HAND_ENDING;
    };

    // Define the set of information that can be received from the server
    this.info = {
            'START': function(game, players) {
                show_message(TranslateMessage['game_start']);
                game.table.setPlayers(players);
            },
            'STARTHAND': function(game, params) {
                if (game.isBlockingPhase()) {
                    setTimeout(() => game.info['STARTHAND'](game, params), 500);
                } else {
                    game.table.resetHandScores();
                    game.updateRuleDisplay('...');
                    setTimeout( () => {
                        game.sendAction('GETHAND', '', (response) => {
                            if (!response.startsWith('ERROR')) game.hand.setCards(JSON.parse(response));
                        });
                    }, 500);

                    game.table.setStarter(params[0]);
                    var startMsg = (params[0] === game.user) ? TranslateMessage['new_hand'][0] : TranslateMessage['starter_msg'](params[0]);
                    show_message(startMsg);

                    if(params[0] === game.user) {
                        game.state = GameStates.WAITING_GAME;
                        game.chooseGame(params.slice(1));
                    } else { game.state = GameStates.PENDING_GAME; }
                }
            },
            'GAME': function(game, choice) {
                if (game.isBlockingPhase()) {
                    setTimeout(() => game.info['GAME'](game, choice), 500);
                } else {
                    game.cur_game = choice[0];
                    game.state = GameStates.RUNNING;
                    game.updateRuleDisplay(choice[0], choice[1]);
                    
                    var ruleLabel = TranslateChoices[choice[0]] || choice[0];
                    var trumpLabel = choice[1] ? (TranslateChoices[choice[1]] || choice[1]) : null;
                    show_message(TranslateMessage['hand_start'](ruleLabel, trumpLabel));
                }
            },
            'TURN': function(game, player) {
                if (game.isBlockingPhase()) {
                    setTimeout(() => game.info['TURN'](game, player), 500);
                } else {
                    game.turn = player[0];
                    game.state = (game.turn == game.user) ? GameStates.WAITING_PLAY : GameStates.RUNNING;
                }
            },
            'PLAY': function(game, card) {
                if (game.isBlockingPhase()) {
                    setTimeout(() => game.info['PLAY'](game, card), 500);
                } else {
                    game.playCard(card[0]);
                }
            },
            'ENDROUND': function(game, winner) {;
                game.state = GameStates.ROUND_ENDING;
                setTimeout( function() {
                    game.table.endRound(winner[0], parseInt(winner[1]));
                    if (game.state === GameStates.ROUND_ENDING) game.state = GameStates.RUNNING;
                }, 1500);
            },
            'ENDHAND': function(game, scores) {
                if (game.state === GameStates.ROUND_ENDING) {
                    setTimeout(() => game.info['ENDHAND'](game, scores), 500);
                } else {
                    game.state = GameStates.HAND_ENDING;
                    game.showHandSummary(scores);
                }
            },
            'GAMEOVER': function(game, score) {
                game.isGameOver = true;
                game.finalScores = score;
                if (!game.isBlockingPhase()) {
                    game.state = GameStates.GAME_OVER;
                    game.showGameOver(score);
                }
            },
            'BID': function(game, player) {
                game.table.setBidder(player[0]);
                if (player[0] === game.user) {
                    if (game.isBlockingPhase()) {
                        setTimeout(() => game.info['BID'](game, player), 500);
                    } else {
                        game.state = GameStates.WAITING_BID;
                        game.getBid();
                    }
                }
            },
            'BIDS': function(game, value) {
                game.table.setBid(value[0]);
            },
            'DECIDE': function(game, player) {
                if (player[0] === game.user) {
                    if (game.isBlockingPhase()) {
                        setTimeout(() => game.info['DECIDE'](game, player), 500);
                    } else {
                        game.state = GameStates.WAITING_DECISION;
                        game.getDecision();
                    }
                }
            },
            'CHOOSETRUMP': function(game, player) {
                if (player[0] === game.user) {
                   if (game.isBlockingPhase()) {
                        setTimeout(() => game.info['CHOOSETRUMP'](game, player), 500);
                    } else {
                        game.state = GameStates.WAITING_TRUMP;
                        game.getTrump();
                    }
                }
            },
            'LEAVE': function(game, player) {
                show_message(TranslateMessage['player_left'](player[0]));
                setTimeout(() => document.getElementById('return-lobby-btn')?.click(), 3000);
            }
        };

    // Start listening on subscription channel
    socket.game = this;
    socket.on('info', function(message) {
        var args = message.split(' ');
        // Strip the message header and use it to call the proper handle
        if (fn = this.game.info[args[0]]) {
            fn(this.game, args.slice(1));
        }
    });
}

function setPlayerName(position, name) {
    switch(position) {
    case PlayerPosition.BOTTOM: 
        $('#player .name').text(`Você (${name})`);
        break;
    case PlayerPosition.TOP: 
        $(`#name${position}`).text(`${name} (Topo)`);
        break;
    case PlayerPosition.LEFT: 
        $(`#name${position}`).text(`${name} (Esquerda)`);
        break;
    case PlayerPosition.RIGHT: 
        $(`#name${position}`).text(`${name} (Direita)`);
        break;
    }
}

function Table(user) {
    this.cards = new Array;
    this.players = {};
    this.hand_score = {};
    this.total_score = {};
    this.table_index = 0;
    this.bids = new Array;
    this.user = user;
    this.current_turn = 0;
    this.current_bidder = 0;
    this.area = document.getElementById('tableCards');

    this.setPlayers = function(players) {
        // This must be rearranged so Current Player is always on
        // the bottom of the screen and next turn is counter clockwise
        this.table_index = players.indexOf(this.user);
        if (this.table_index === -1) {
            // This should never happen ... user is not part of the table
            return;
        }
        for(var i = PlayerPosition.BOTTOM; i < PlayerPosition.CAPACITY; i++ ) {
            var pos = (this.table_index + i) % PlayerPosition.CAPACITY;
            var name = players[pos];
            this.players[name] = i;
            this.hand_score[name] = 0;
            this.total_score[name] = 0;
            setPlayerName(i, name);
        }
    };

    this.setStarter = function(starter) {
        this.current_turn = this.players[starter];
        this.bids = [-1, -1, -1, -1];
        this.bids[this.current_turn] = -2;
        this.bid_history = [];
    };
    
    this.addCard = function(card) {
        this.cards.push(card);
        var rank = card.slice(0, -1);
        var suit = card.slice(-1);
        var node = (new Card(rank, suit)).createNode();
        node.style.transformOrigin = 'center center';
        this.area.appendChild(node);

        $(node).playKeyframe(`tableCard${this.current_turn} 2s forwards`);

        this.current_turn = (this.current_turn + 1) % PlayerPosition.CAPACITY;
    };

    this.endRound = function(winner, score) {
        this.cards = new Array;
        
        // Display a message to notify the round winner
        var msg = '';
        this.hand_score[winner] += score;
        $(`#score${this.players[winner]}`).text(`${this.hand_score[winner]} / ${this.total_score[winner]}`);

        if( winner === this.user) {
            msg = TranslateMessage['round_win'][0];
        } else {
            msg = TranslateMessage['round_win'][1](winner);
        }
        show_message(msg, '2s');

        //TODO: Animate cards going to winners side
        while(this.area.hasChildNodes()) {
            this.area.removeChild(this.area.lastChild);
        }

        this.setStarter(winner);
    };

    this.endHand = function(scores) {
        for (var name in this.players) {
            var pos = this.players[name];
            var value = parseInt(scores[(this.table_index + pos) % PlayerPosition.CAPACITY]);
            this.hand_score[name] = value;
            this.total_score[name] += value;
            $(`#score${pos}`).text(`${this.hand_score[name]} / ${this.total_score[name]}`);
        }
    };

    this.resetHandScores = function() {
        for (var name in this.players) {
            var pos = this.players[name];
            this.hand_score[name] = 0;
            $(`#score${pos}`).text(`${this.hand_score[name]} / ${this.total_score[name]}`);
        }
    };

    this.setTotalScores = function(scores) {
        for (var name in this.players) {
            var pos = this.players[name];
            var value = parseInt(scores[(this.table_index + pos) % PlayerPosition.CAPACITY]);
            this.total_score[name] = value;
            $(`#score${pos}`).text(`${this.hand_score[name]} / ${this.total_score[name]}`);
        }
    };

    this.setBidder = function(bidder) {
        this.current_bidder = this.players[bidder];
    };

    this.setBid = function(bid) {
        var bidVal = parseInt(bid);
        this.bids[this.current_bidder] = bidVal;
        
        var playerName = Object.keys(this.players).find(key => this.players[key] === this.current_bidder) || "Alguém";
        this.bid_history.push({ player: playerName, bid: bidVal });
    };
}

function Hand(game) {
    this.cards = new Array;
    this.hand_area = document.getElementById('playerCards');

    this.createClickCallback = function(card) {
        return function(evt) {
            game.play(card);
        };
    }

    this.setCards = function(cards) {
        // Sort cards: Suit alphabetical (C, D, H, S), then rank (2..A)
        var rankOrder = { '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14 };
        cards.sort(function(a, b) {
            var suitA = a.slice(-1);
            var suitB = b.slice(-1);
            if (suitA !== suitB) {
                return suitA.localeCompare(suitB);
            }
            var rankA = a.slice(0, -1);
            var rankB = b.slice(0, -1);
            return rankOrder[rankA] - rankOrder[rankB];
        });

        this.cards = cards;
        this.emptyHand();

        // Create cards and set animation
        for (var i = 0; i < cards.length; i++) {
            var card = cards[i];
            var rank = card.slice(0, -1);
            var suit = card.slice(-1);
            var node = (new Card(rank, suit)).createNode();
            node.onclick = this.createClickCallback(card);
            $(node).playKeyframe(`handCard${i} 3s forwards`);
            
            this.hand_area.appendChild(node);
        }
    }

    this.emptyHand = function() {
        while(this.hand_area.hasChildNodes()) {
            this.hand_area.removeChild(this.hand_area.lastChild);
        }
    }

    this.playCard = function(card) {
        //TODO: Animate card when leaving hand
        var index = this.cards.indexOf(card);
        
        if (index !== -1) {
            this.cards.splice(index, 1);
            var node = this.hand_area.childNodes[index];
            this.hand_area.removeChild(node);
        }
    }
}

function authorize(game, password) {
        // I'm ignoring response here, since I don't really care
        socket.once('response', function(msg){
            if (!msg.startsWith('ERROR')) {
                show_message(TranslateMessage['authorize']);
                game.channel = msg;
            }
        });
        socket.emit('action', `AUTHORIZE ${game.user} ${password}`);
}

function hunt_table(game) {
    var fnJoinAny = function(msg) {
        if (msg.startsWith('ERROR')) {
            show_message(TranslateMessage['join_fail']);
            return;
        }

        var tables = JSON.parse(msg);
        if (tables.length > 0) {
            game.secret = game.channel
            game.sendAction('JOIN', tables[0]['name'], function(msg) {
                if (!msg.startsWith('ERROR')) {
                    show_message(TranslateMessage['join_succ'])
                    game.secret = msg;
                }
            });
        } else {
            // I'm ignoring response here, since I don't really care
            socket.once('response', function(msg){
                socket.once('response', fnJoinAny);
                socket.emit('action', 'LIST');
            });
            socket.emit('action', `TABLE ${game.user} ${game.channel}`);
        }
    };

    socket.once('response', fnJoinAny);
    socket.emit('action', 'LIST');
}

function show_message(message, duration='3s') {
    var box = document.getElementById('infobox');

    if (box.classList.contains('animated')) {
        setTimeout(function() {
            show_message(message);
        }, 500);
    } else {
        var content = document.getElementById('infocontent')
        content.textContent = message;

        box.addEventListener('animationend', function(evt) {
            box.style.animation = "";
            box.classList.remove('animated');
        });
        box.classList.add('animated');
        box.style.animation = `showinfo ${duration} ease-out 0s forwards`;
    }
}
