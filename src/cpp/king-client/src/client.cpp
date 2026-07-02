#include "king/client.h"
#include <zmq.hpp>
#include <nlohmann/json.hpp>
#include <sstream>
#include <mutex>
#include <queue>
#include <thread>
#include <atomic>
#include <vector>
#include <functional>
#include <iostream>

namespace king {

struct RequestTask {
    std::string command;
    std::function<void(const std::string&)> callback;
};

struct KingClient::Impl {
    zmq::context_t context;
    std::unique_ptr<zmq::socket_t> reqSocket;
    std::unique_ptr<zmq::socket_t> subSocket;

    std::string hostAddress;
    int reqPort = 5555;
    int subPort = 5556;

    std::thread workerThread;
    std::atomic<bool> shouldStop{false};
    std::atomic<bool> isConnected{false};

    // Subscriptions queued from user thread to worker thread
    std::mutex subMutex;
    std::vector<std::string> pendingSubscriptions;
    std::vector<std::string> pendingUnsubscriptions;

    // Requests queued from user thread to worker thread
    std::mutex outboxMutex;
    std::vector<RequestTask> outbox;

    // Callbacks queued from worker thread to user thread (for main thread execution)
    std::mutex callbackMutex;
    std::vector<std::function<void()>> pendingCallbacks;

    // Pub/Sub callbacks
    std::function<void(const std::string&, const std::vector<std::string>&)> onGameStart;
    std::function<void(const std::string&, const std::string&, const std::vector<Rule>&)> onHandStart;
    std::function<void(const std::string&, const std::string&)> onTurn;
    std::function<void(const std::string&, const std::string&)> onBidTurn;
    std::function<void(const std::string&, const std::string&, int)> onBid;
    std::function<void(const std::string&, Rule, Suit)> onGameChosen;
    std::function<void(const std::string&, const Card&)> onCardPlayed;
    std::function<void(const std::string&, const std::string&, int)> onEndRound;
    std::function<void(const std::string&, const std::vector<int>&)> onEndHand;
    std::function<void(const std::string&, const std::vector<int>&)> onGameOver;
    std::function<void(const std::string&, const std::string&)> onLeave;
    std::function<void(const std::string&)> onAskJoin;
    std::function<void(const std::vector<std::string>&)> onUserList;
    std::string authorizedUsername;
    std::string sessionChannel;

    Impl() : context(1) {}

    void queue_callback(std::function<void()> cb) {
        std::lock_guard<std::mutex> lock(callbackMutex);
        pendingCallbacks.push_back(cb);
    }

    void send_req(const std::string& cmd, std::function<void(const std::string&)> cb) {
        std::lock_guard<std::mutex> lock(outboxMutex);
        outbox.push_back(RequestTask{cmd, cb});
    }

    void thread_loop() {
        std::string reqUrl = "tcp://" + hostAddress + ":" + std::to_string(reqPort);
        std::string subUrl = "tcp://" + hostAddress + ":" + std::to_string(subPort);
        int linger = 0;
        int timeout = 500; // 500ms timeout

        try {
            reqSocket = std::make_unique<zmq::socket_t>(context, zmq::socket_type::req);
            subSocket = std::make_unique<zmq::socket_t>(context, zmq::socket_type::sub);

            reqSocket->set(zmq::sockopt::linger, linger);
            reqSocket->set(zmq::sockopt::rcvtimeo, timeout);
            reqSocket->set(zmq::sockopt::sndtimeo, timeout);
            subSocket->set(zmq::sockopt::linger, linger);

            reqSocket->connect(reqUrl);
            subSocket->connect(subUrl);
            isConnected = true;

            while (!shouldStop) {
                // 1. Process subscription/unsubscription requests
                {
                    std::lock_guard<std::mutex> lock(subMutex);
                    for (const auto& topic : pendingSubscriptions) {
                        subSocket->set(zmq::sockopt::subscribe, topic);
                    }
                    pendingSubscriptions.clear();

                    for (const auto& topic : pendingUnsubscriptions) {
                        subSocket->set(zmq::sockopt::unsubscribe, topic);
                    }
                    pendingUnsubscriptions.clear();
                }

                // 2. Process outbox requests (REQ/REP)
                std::vector<RequestTask> localOutbox;
                {
                    std::lock_guard<std::mutex> lock(outboxMutex);
                    if (!outbox.empty()) {
                        localOutbox = std::move(outbox);
                        outbox.clear();
                    }
                }

                for (const auto& task : localOutbox) {
                    try {
                        reqSocket->send(zmq::buffer(task.command), zmq::send_flags::none);

                        zmq::message_t reply;
                        auto res = reqSocket->recv(reply, zmq::recv_flags::none);
                        if (res) {
                            std::string replyStr(static_cast<char*>(reply.data()), reply.size());
                            queue_callback([cb = task.callback, replyStr]() {
                                cb(replyStr);
                            });
                        }
                    } catch (const zmq::error_t& e) {
                        // Recreate REQ socket to clear state
                        reqSocket = std::make_unique<zmq::socket_t>(context, zmq::socket_type::req);
                        reqSocket->set(zmq::sockopt::linger, linger);
                        reqSocket->set(zmq::sockopt::rcvtimeo, timeout);
                        reqSocket->set(zmq::sockopt::sndtimeo, timeout);
                        reqSocket->connect(reqUrl);

                        queue_callback([cb = task.callback, msg = "ERROR " + std::string(e.what())]() {
                            cb(msg);
                        });
                    }
                }

                // 3. Poll SUB socket for pub/sub messages
                zmq_pollitem_t items[] = {
                    { static_cast<void*>(*subSocket), 0, ZMQ_POLLIN, 0 }
                };

                int rc = zmq::poll(&items[0], 1, std::chrono::milliseconds(10));
                if (rc > 0 && (items[0].revents & ZMQ_POLLIN)) {
                    try {
                        zmq::message_t msg;
                        auto res = subSocket->recv(msg, zmq::recv_flags::none);
                        if (res) {
                            std::string fullMsg(static_cast<char*>(msg.data()), msg.size());
                            size_t spacePos = fullMsg.find(' ');
                            if (spacePos != std::string::npos) {
                                std::string topic = fullMsg.substr(0, spacePos);
                                std::string payload = fullMsg.substr(spacePos + 1);
                                handle_sub_message(topic, payload);
                            }
                        }
                    } catch (const zmq::error_t& /*e*/) {
                        // Ignore SUB errors
                    }
                }

                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
        } catch (const std::exception& e) {
            std::cerr << "KingClient worker thread exception: " << e.what() << std::endl;
        }

        isConnected = false;
    }

    void handle_sub_message(const std::string& topic, const std::string& payload) {
        std::vector<std::string> args;
        std::stringstream ss(payload);
        std::string arg;
        while (ss >> arg) {
            args.push_back(arg);
        }

        if (args.empty()) return;

        std::string cmd = args[0];

        if (cmd == "START" && args.size() >= 5) {
            std::vector<std::string> players(args.begin() + 1, args.end());
            queue_callback([this, topic, players]() {
                if (onGameStart) onGameStart(topic, players);
            });
        } 
        else if (cmd == "STARTHAND" && args.size() >= 3) {
            std::string starter = args[1];
            std::vector<Rule> rules;
            for (size_t i = 2; i < args.size(); ++i) {
                rules.push_back(string_to_rule(args[i]));
            }
            queue_callback([this, topic, starter, rules]() {
                if (onHandStart) onHandStart(topic, starter, rules);
            });
        } 
        else if (cmd == "TURN" && args.size() >= 2) {
            std::string player = args[1];
            queue_callback([this, topic, player]() {
                if (onTurn) onTurn(topic, player);
            });
        } 
        else if (cmd == "BID" && args.size() >= 2) {
            std::string player = args[1];
            queue_callback([this, topic, player]() {
                if (onBidTurn) onBidTurn(topic, player);
            });
        } 
        else if (cmd == "BIDS" && args.size() >= 2) {
            try {
                int value = std::stoi(args[1]);
                queue_callback([this, topic, value]() {
                    if (onBid) onBid(topic, "", value); // Python-style, we can infer name from state or pass empty
                });
            } catch (...) {}
        } 
        else if (cmd == "GAME" && args.size() >= 2) {
            Rule r = string_to_rule(args[1]);
            Suit s = Suit::None;
            if (args.size() >= 3) {
                char suitChar = args[2][0];
                if (suitChar == 'S') s = Suit::Spades;
                else if (suitChar == 'H') s = Suit::Hearts;
                else if (suitChar == 'D') s = Suit::Diamonds;
                else if (suitChar == 'C') s = Suit::Clubs;
            }
            queue_callback([this, topic, r, s]() {
                if (onGameChosen) onGameChosen(topic, r, s);
            });
        } 
        else if (cmd == "PLAY" && args.size() >= 2) {
            Card c = Card::parse(args[1]);
            queue_callback([this, topic, c]() {
                if (onCardPlayed) onCardPlayed(topic, c);
            });
        } 
        else if (cmd == "ENDROUND" && args.size() >= 3) {
            std::string winner = args[1];
            try {
                int score = std::stoi(args[2]);
                queue_callback([this, topic, winner, score]() {
                    if (onEndRound) onEndRound(topic, winner, score);
                });
            } catch (...) {}
        } 
        else if (cmd == "ENDHAND") {
            std::vector<int> scores;
            for (size_t i = 1; i < args.size(); ++i) {
                try { scores.push_back(std::stoi(args[i])); } catch (...) {}
            }
            queue_callback([this, topic, scores]() {
                if (onEndHand) onEndHand(topic, scores);
            });
        } 
        else if (cmd == "GAMEOVER") {
            std::vector<int> scores;
            for (size_t i = 1; i < args.size(); ++i) {
                try { scores.push_back(std::stoi(args[i])); } catch (...) {}
            }
            queue_callback([this, topic, scores]() {
                if (onGameOver) onGameOver(topic, scores);
            });
        } 
        else if (cmd == "LEAVE" && args.size() >= 2) {
            std::string player = args[1];
            queue_callback([this, topic, player]() {
                if (onLeave) onLeave(topic, player);
            });
        } 
        else if (cmd == "ASKJOIN" && args.size() >= 2) {
            std::string tableUuid = args[1];
            queue_callback([this, tableUuid]() {
                if (onAskJoin) onAskJoin(tableUuid);
            });
        }
        else if (cmd == "CONFIRM_AVAILABLE") {
            std::string respCmd = "AVAILABLE " + authorizedUsername + " " + sessionChannel;
            send_req(respCmd, [](const std::string& /*reply*/) {
                // ignore
            });
        }
        else if (cmd == "USERLIST") {
            std::vector<std::string> users;
            for (size_t i = 1; i < args.size(); ++i) {
                users.push_back(args[i]);
            }
            queue_callback([this, users]() {
                if (onUserList) onUserList(users);
            });
        }
    }
};

KingClient::KingClient() : impl_(std::make_unique<Impl>()) {}

KingClient::~KingClient() {
    disconnect();
}

bool KingClient::connect(const std::string& host, int req_port, int sub_port) {
    disconnect();
    impl_->hostAddress = host;
    impl_->reqPort = req_port;
    impl_->subPort = sub_port;
    impl_->shouldStop = false;
    impl_->workerThread = std::thread(&Impl::thread_loop, impl_.get());
    return true;
}

void KingClient::disconnect() {
    impl_->shouldStop = true;
    if (impl_->workerThread.joinable()) {
        impl_->workerThread.join();
    }
}

bool KingClient::is_connected() const {
    return impl_->isConnected;
}

void KingClient::update() {
    std::vector<std::function<void()>> localCallbacks;
    {
        std::lock_guard<std::mutex> lock(impl_->callbackMutex);
        if (!impl_->pendingCallbacks.empty()) {
            localCallbacks = std::move(impl_->pendingCallbacks);
            impl_->pendingCallbacks.clear();
        }
    }
    for (const auto& cb : localCallbacks) {
        cb();
    }
}



void KingClient::authorize(const std::string& username, const std::string& password,
                           std::function<void(bool success, const std::string& channel_or_error)> cb) {
    std::string cmd = "AUTHORIZE " + username + " " + password;
    impl_->send_req(cmd, [this, username, cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            impl_->authorizedUsername = username;
            impl_->sessionChannel = reply; // The reply to AUTHORIZE is the session channel
            subscribe(reply); // Automatically subscribe to our private session channel
            cb(true, reply);
        }
    });
}

void KingClient::list_tables(std::function<void(const std::vector<Table>& tables, const std::string& error)> cb) {
    impl_->send_req("LIST", [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb({}, reply.substr(6));
        } else {
            try {
                auto j = nlohmann::json::parse(reply);
                std::vector<Table> tables;
                for (const auto& item : j) {
                    Table t;
                    t.name = item["name"].get<std::string>();
                    t.players = item["players"].get<std::vector<std::string>>();
                    tables.push_back(t);
                }
                cb(tables, "");
            } catch (const std::exception& e) {
                cb({}, "Failed to parse JSON reply: " + std::string(e.what()));
            }
        }
    });
}

void KingClient::create_table(const std::string& username, const std::string& channel,
                              std::function<void(const std::string& table_uuid, const std::string& error)> cb) {
    std::string cmd = "TABLE " + username + " " + channel;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb("", reply.substr(6));
        } else {
            cb(reply, "");
        }
    });
}

void KingClient::join_table(const std::string& username, const std::string& channel, const std::string& table_uuid,
                            std::function<void(const std::string& player_secret, const std::string& error)> cb) {
    std::string cmd = "JOIN " + username + " " + channel + " " + table_uuid;
    impl_->send_req(cmd, [this, table_uuid, cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb("", reply.substr(6));
        } else {
            subscribe(table_uuid); // Automatically subscribe to the table's updates
            cb(reply, "");
        }
    });
}

void KingClient::get_hand(const std::string& username, const std::string& secret,
                          std::function<void(const std::vector<Card>& hand, const std::string& error)> cb) {
    std::string cmd = "GETHAND " + username + " " + secret;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb({}, reply.substr(6));
        } else {
            try {
                auto j = nlohmann::json::parse(reply);
                std::vector<Card> hand;
                for (const auto& item : j) {
                    hand.push_back(Card::parse(item.get<std::string>()));
                }
                cb(hand, "");
            } catch (const std::exception& e) {
                cb({}, "Failed to parse hand JSON: " + std::string(e.what()));
            }
        }
    });
}

void KingClient::get_turn(const std::string& username, const std::string& secret,
                          std::function<void(const std::string& active_player, const std::string& error)> cb) {
    std::string cmd = "GETTURN " + username + " " + secret;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb("", reply.substr(6));
        } else {
            cb(reply, "");
        }
    });
}

void KingClient::choose_rule(const std::string& username, const std::string& secret, Rule rule,
                             std::function<void(bool success, const std::string& error)> cb) {
    std::string cmd = "GAME " + username + " " + secret + " " + rule_to_string(rule);
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::bid(const std::string& username, const std::string& secret, int value,
                     std::function<void(bool success, const std::string& error)> cb) {
    std::string cmd = "BID " + username + " " + secret + " " + std::to_string(value);
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::decide(const std::string& username, const std::string& secret, bool accept,
                        std::function<void(bool success, const std::string& error)> cb) {
    std::string decisionStr = accept ? "True" : "False";
    std::string cmd = "DECIDE " + username + " " + secret + " " + decisionStr;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::choose_trump(const std::string& username, const std::string& secret, Suit suit,
                              std::function<void(bool success, const std::string& error)> cb) {
    std::string suitStr;
    switch (suit) {
        case Suit::Spades:   suitStr = "S"; break;
        case Suit::Hearts:   suitStr = "H"; break;
        case Suit::Diamonds: suitStr = "D"; break;
        case Suit::Clubs:    suitStr = "C"; break;
        default:             suitStr = "?"; break;
    }
    std::string cmd = "TRUMP " + username + " " + secret + " " + suitStr;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::play_card(const std::string& username, const std::string& secret, const Card& card,
                           std::function<void(bool success, const std::string& error)> cb) {
    std::string cmd = "PLAY " + username + " " + secret + " " + card.to_string();
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::leave_game(const std::string& username, const std::string& secret,
                            std::function<void(bool success, const std::string& error)> cb) {
    std::string cmd = "LEAVE " + username + " " + secret;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::subscribe(const std::string& topic) {
    std::lock_guard<std::mutex> lock(impl_->subMutex);
    impl_->pendingSubscriptions.push_back(topic);
}

void KingClient::unsubscribe(const std::string& topic) {
    std::lock_guard<std::mutex> lock(impl_->subMutex);
    impl_->pendingUnsubscriptions.push_back(topic);
}

// Callback registration helpers
void KingClient::set_on_game_start(std::function<void(const std::string&, const std::vector<std::string>&)> cb) {
    impl_->onGameStart = cb;
}
void KingClient::set_on_hand_start(std::function<void(const std::string&, const std::string&, const std::vector<Rule>&)> cb) {
    impl_->onHandStart = cb;
}
void KingClient::set_on_turn(std::function<void(const std::string&, const std::string&)> cb) {
    impl_->onTurn = cb;
}
void KingClient::set_on_bid_turn(std::function<void(const std::string&, const std::string&)> cb) {
    impl_->onBidTurn = cb;
}
void KingClient::set_on_bid(std::function<void(const std::string&, const std::string&, int)> cb) {
    impl_->onBid = cb;
}
void KingClient::set_on_game_chosen(std::function<void(const std::string&, Rule, Suit)> cb) {
    impl_->onGameChosen = cb;
}
void KingClient::set_on_card_played(std::function<void(const std::string&, const Card&)> cb) {
    impl_->onCardPlayed = cb;
}
void KingClient::set_on_end_round(std::function<void(const std::string&, const std::string&, int)> cb) {
    impl_->onEndRound = cb;
}
void KingClient::set_on_end_hand(std::function<void(const std::string&, const std::vector<int>&)> cb) {
    impl_->onEndHand = cb;
}
void KingClient::set_on_game_over(std::function<void(const std::string&, const std::vector<int>&)> cb) {
    impl_->onGameOver = cb;
}
void KingClient::set_on_leave(std::function<void(const std::string&, const std::string&)> cb) {
    impl_->onLeave = cb;
}
void KingClient::set_on_ask_join(std::function<void(const std::string&)> cb) {
    impl_->onAskJoin = cb;
}

void KingClient::set_on_user_list(std::function<void(const std::vector<std::string>&)> cb) {
    impl_->onUserList = cb;
}

void KingClient::leave_table(const std::string& username, const std::string& secret,
                             std::function<void(bool success, const std::string& error)> cb) {
    std::string cmd = "LEAVE " + username + " " + secret;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::list_users(std::function<void(bool success, const std::string& error)> cb) {
    subscribe("user-list-channel");
    impl_->send_req("LISTUSERS", [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb(false, reply.substr(6));
        } else {
            cb(true, "");
        }
    });
}

void KingClient::invite_match(const std::string& username, const std::string& channel,
                              const std::string& p2, const std::string& p3, const std::string& p4,
                              std::function<void(const std::string& table_uuid, const std::string& error)> cb) {
    std::string cmd = "MATCH " + username + " " + channel + " " + p2 + " " + p3 + " " + p4;
    impl_->send_req(cmd, [cb](const std::string& reply) {
        if (reply.rfind("ERROR", 0) == 0) {
            cb("", reply.substr(6));
        } else {
            cb(reply, "");
        }
    });
}

} // namespace king
