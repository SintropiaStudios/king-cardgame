use std::env;
use std::fmt;
use rand::Rng;

// For parsing some of the server responses in JSON
use serde::{Deserialize, Serialize};

#[derive(Debug)]
struct Player 
    { name:     String
    , channel:  String
    }

#[derive(Serialize, Deserialize, Debug)]
struct Table
    { name:     String
    , players:  Vec<String>
    }

type KingCard = String;
type KingRule = String;

#[derive(Debug)]
struct KingHand
    { rule:         KingRule
    , cur_round:    Vec<KingCard>
    , rounds:       Vec<(String, i32, Vec<KingCard>)>
    , score:        [i32; 4]
    }

#[derive(Debug)]
enum GameAction 
    { Wait
    , ChooseRule
    , Play
    , Bid
    , Decide
    , ChooseTrump
    }

impl fmt::Display for GameAction {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            GameAction::ChooseRule => write!(f, "GAME"),
            GameAction::Play => write!(f, "PLAY"),
            GameAction::Bid => write!(f, "BID"),
            GameAction::Decide => write!(f, "DECIDE"),
            GameAction::ChooseTrump => write!(f, "GAME POSITIVA"),
            _ => write!(f, "LEAVE")
        }
    }
}

#[derive(Debug)]
struct KingGame
    { player:     Player
    , table:      Table
    , secret:     String
    , hands:      Vec<KingHand>
    , cards:      Vec<KingCard>
    , rules:      Option<Vec<String>>
    , cur_player: String
    , expected:   GameAction
    }

impl KingGame {
    fn play_card(&mut self, player: &str, card: &str) {
        let hand = self.hands.last_mut().unwrap();
        hand.cur_round.push(String::from(card));
        if self.player.name == player {
            let index = self.cards.iter().position(|x| *x == card).unwrap();
            self.cards.remove(index);
        }
    }

    fn end_round(&mut self, player: &str, score: i32) {
        let mut hand = self.hands.last_mut().unwrap();
        hand.rounds.push((String::from(player), score, hand.cur_round.clone()));
        hand.cur_round = Vec::new();
    }

    fn evaluate(&mut self, manager: &GameManager, info: String) -> bool {
        let args : Vec<String> = info.split(" ").map(|s| String::from(s)).collect();

        if args.len() < 2 || args[0] != self.table.name {
            println!("Badly formatted message or directed to another table");
            return true;
        }

        self.expected = GameAction::Wait; // Just a default
        match args[1].as_str() {
            "START" => {
                self.table.players = args[1..].to_vec();
            },
            "STARTHAND" => {
                // The only reason why I need the manager here is for this interaction
                // I need to get the player's cards so he can have an informed decision
                manager.get_player_cards(self);

                if self.player.name == args[2] {
                    self.rules = Some(args[3..].to_vec());
                    self.expected = GameAction::ChooseRule;
                }
            },
            "GAME" => {
                self.hands.push(KingHand {rule: String::from(args[2].as_str()), cur_round: Vec::new(), rounds: Vec::new(), score: [0,0,0,0]});
            },
            "TURN" => {
                if self.player.name == args[2] {
                    self.expected = GameAction::Play;
                }
                self.cur_player = args[2].clone();
            },
            "PLAY" => {
                let cur_player = self.cur_player.clone();
                self.play_card(&cur_player, &args[2]);
            },
            "BID" => {
                if self.player.name == args[2] {
                    self.expected = GameAction::Bid;
                }
            },
            "BIDS" => {
                println!("A player bids a value");
            },
            "DECIDE" => {
                if self.player.name == args[2] {
                    self.expected = GameAction::Decide;
                }
            },
            "CHOOSETRUMP" => {
                if self.player.name == args[2] {
                    self.expected = GameAction::ChooseTrump;
                }
            },
            "ENDROUND" => {
                self.end_round(&args[2], args[3].parse().unwrap());
            },
            "ENDHAND" => {
                //args[2],3,4,5 are i32
                println!("Hand has ended.");
            },
            "GAMEOVER" => {
                println!("The game has ended.");
                return false;
            }
            _ => {
                println!("Unknown Message");
            }
        };

        true
    }
}

struct GameManager
    { req_skt:      zmq::Socket
    , sub_skt:      zmq::Socket
    }

fn setup_manager(base_url: &str) -> GameManager {
    let ctx = zmq::Context::new();
    let req = ctx.socket(zmq::REQ).unwrap();
    let sub = ctx.socket(zmq::SUB).unwrap();

    assert!(req.connect(&format!("{}:5555", base_url)).is_ok());
    assert!(sub.connect(&format!("{}:5556", base_url)).is_ok());

    GameManager
    { req_skt: req
    , sub_skt: sub
    }
}

impl GameManager {
    fn authorize_player(&self, username:String, password:String) -> Player {
        let mut msg = zmq::Message::new();
    
        let action = format!("AUTHORIZE {} {}", username, password);
        self.req_skt.send(&action, 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let rsp = String::from(msg.as_str().unwrap());
        assert!(!rsp.starts_with("ERROR"));

        Player {name: username, channel: rsp}
    }

    fn list_tables(&self) -> Vec<Table> {
        let mut msg = zmq::Message::new();

        self.req_skt.send("LIST", 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let data = String::from(msg.as_str().unwrap());
        assert!(!data.starts_with("ERROR"));

        serde_json::from_str(&data).expect("Error parsing JSON from server")
    }

    fn join_table(&self, player: Player, table: Table) -> KingGame {
        let mut msg = zmq::Message::new();

        self.sub_skt.set_subscribe(table.name.as_bytes()).unwrap();
    
        self.req_skt.send(&format!("JOIN {} {} {}", player.name, player.channel, table.name), 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let data = String::from(msg.as_str().unwrap());
        assert!(!data.starts_with("ERROR"));

        KingGame { player: player, table: table, secret: data, hands: Vec::new(), cards: Vec::new(), rules: None, expected: GameAction::Wait, cur_player: String::from("") }
    }

    fn create_table(&self, player: &Player) -> Table {
        let mut msg = zmq::Message::new();

        self.req_skt.send(&format!("TABLE {} {}", player.name, player.channel), 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let data = String::from(msg.as_str().unwrap());
        assert!(!data.starts_with("ERROR"));

        Table { name: data, players: Vec::new() }
    }

    fn hunt_table(&self, player: Player) -> KingGame {
        loop {
            let mut lst = self.list_tables();
            if lst.len() == 0 {
                self.create_table(&player);
            } else {
                break self.join_table(player, lst.pop().unwrap());
            };
        }
    }

    fn leave_game(&self, game: KingGame) -> () {
        let mut msg = zmq::Message::new();

        self.req_skt.send(&format!("LEAVE {} {}", game.player.name, game.secret), 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let _data = String::from(msg.as_str().unwrap());
    }

    fn get_player_cards(&self, game: &mut KingGame) -> () {
        let mut msg = zmq::Message::new();

        self.req_skt.send(&format!("GETHAND {} {}", game.player.name, game.secret), 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let data = String::from(msg.as_str().unwrap());
        assert!(!data.starts_with("ERROR"));

        let cards : Vec<String> = serde_json::from_str(&data).expect("Error parsing JSON from server");
        game.cards = cards;
    }

    pub fn update_game(&self, game: &mut KingGame) -> bool {
        let mut items = [ self.sub_skt.as_poll_item(zmq::POLLIN) ];
        
        //timeout in ms, -1 for INFINITE
        zmq::poll(&mut items, 1000).unwrap();
        if items[0].is_readable() {
            let mut msg = zmq::Message::new();
            assert!(self.sub_skt.recv(&mut msg, 0).is_ok());

            let info = String::from(msg.as_str().unwrap());
            println!("Server: {}", info);
            
            return game.evaluate(self, info);
        }

        true
    }

    pub fn take_action(&self, game: &KingGame, action: GameAction, args: Option<String>) -> bool {
        let mut msg = zmq::Message::new();
        let mut act = format!("{} {} {}", action, game.player.name, game.secret);
        if args.is_some() {
            act += &format!(" {}", args.unwrap());
        }

        self.req_skt.send(&act, 0).unwrap();
        self.req_skt.recv(&mut msg, 0).unwrap();
    
        let data = String::from(msg.as_str().unwrap());
        data.starts_with("ACK")
    }
}


fn main() {
    let args: Vec<String> = env::args().collect();

    let name:String = args[1].parse().unwrap();
    let pwrd:String = args[2].parse().unwrap();

    let manager = setup_manager("tcp://127.0.0.1");

    println!("Authorizing user {} ....", name);
    let p = manager.authorize_player(name, pwrd);
    println!(".... Done, {:?}", p);
    let mut g = manager.hunt_table(p);

    loop {
        if !manager.update_game(&mut g) {
            break;
        }
        
        match g.expected {
            GameAction::ChooseRule => {
                println!("{:?}", g);
                match &g.rules {
                    None => {},
                    Some(rs) => {
                        manager.take_action(&g, GameAction::ChooseRule, Some(rs[0].clone()));
                    }
                };
            },
            GameAction::Play => {
                println!("{:?}", g);
                let num_cards = g.cards.len();
                let choice = rand::thread_rng().gen_range(0..num_cards);
                manager.take_action(&g, GameAction::Play, Some(g.cards[choice].clone()));
            },
            GameAction::Decide => {
                println!("{:?}", g);
                manager.take_action(&g, GameAction::Decide, Some(String::from("False")));
            },
            GameAction::Bid => {
                println!("{:?}", g);
                manager.take_action(&g, GameAction::Bid, Some(String::from("0")));
            },
            GameAction::ChooseTrump => {
                println!("{:?}", g);
                manager.take_action(&g, GameAction::ChooseTrump, Some(String::from("H")));
            },
            _ => {
            }
        };
    }

    manager.leave_game(g);
}
