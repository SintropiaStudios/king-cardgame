#include "king/client.h"
#include <iostream>
#include <chrono>
#include <thread>
#include <random>
#include <algorithm>

using namespace king;

struct AgentState {
    std::string username;
    std::string password;
    std::string secret;
    std::string activeTable;
    std::vector<Card> hand;
    std::vector<std::string> players;
    bool isMyTurn = false;
    bool isMyRuleChoice = false;
    bool isMyBid = false;
    bool isMyDecision = false;
    bool isMyTrumpChoice = false;
    std::vector<Rule> selectableRules;
    std::string trumpChooser;
    bool isRunning = true;
};

int main(int argc, char* argv[]) {
    std::string host = "127.0.0.1";
    std::string username = "AgentC++";
    std::string password = "okn_pass";

    if (argc >= 2) host = argv[1];
    if (argc >= 3) username = argv[2];
    if (argc >= 4) password = argv[3];

    std::cout << "Starting C++ King Agent: " << username << " connecting to " << host << "..." << std::endl;

    KingClient client;
    if (!client.connect(host)) {
        std::cerr << "Failed to initialize network sockets." << std::endl;
        return 1;
    }

    AgentState state;
    state.username = username;
    state.password = password;

    // Set up random number generator
    std::random_device rd;
    std::mt19937 g(rd());

    // Register PUB/SUB event callbacks
    client.set_on_game_start([&](const std::string& table, const std::vector<std::string>& players) {
        std::cout << "\n[EVENT] Game Started on table " << table << "! Players: ";
        for (const auto& p : players) std::cout << p << " ";
        std::cout << std::endl;
        state.players = players;
    });

    client.set_on_hand_start([&](const std::string& table, const std::string& starter, const std::vector<Rule>& rules) {
        std::cout << "\n[EVENT] Hand Started! Starter: " << starter << std::endl;
        
        // Fetch new hand
        client.get_hand(state.username, state.secret, [&](const std::vector<Card>& hand, const std::string& err) {
            if (!err.empty()) {
                std::cerr << "Error getting hand: " << err << std::endl;
                return;
            }
            state.hand = hand;
            std::cout << "My Hand: ";
            for (const auto& c : state.hand) std::cout << c.to_string() << " ";
            std::cout << std::endl;

            // If it's my turn to choose the rule
            if (starter == state.username) {
                std::cout << "My turn to choose a rule! Options: ";
                for (auto r : rules) std::cout << rule_to_string(r) << " ";
                std::cout << std::endl;

                state.isMyRuleChoice = true;
                state.selectableRules = rules;
            }
        });
    });

    client.set_on_turn([&](const std::string& /*table*/, const std::string& player) {
        std::cout << "[EVENT] Turn: " << player << std::endl;
        if (player == state.username) {
            state.isMyTurn = true;
        }
    });

    client.set_on_bid_turn([&](const std::string& /*table*/, const std::string& player) {
        std::cout << "[EVENT] Bid Turn: " << player << std::endl;
        if (player == state.username) {
            state.isMyBid = true;
        }
    });

    client.set_on_bid([&](const std::string& /*table*/, const std::string& player, int value) {
        std::cout << "[EVENT] Bids info: " << player << " bid " << value << std::endl;
    });

    client.set_on_game_chosen([&](const std::string& /*table*/, Rule rule, Suit trump) {
        std::string trumpStr = (trump == Suit::None) ? "" : " (Trump: " + std::string(1, "SHDCN"[static_cast<int>(trump)]) + ")";
        std::cout << "[EVENT] Game chosen: " << rule_to_string(rule) << trumpStr << std::endl;
    });

    client.set_on_card_played([&](const std::string& /*table*/, const Card& card) {
        std::cout << "[EVENT] Card Played: " << card.to_string() << std::endl;
    });

    client.set_on_end_round([&](const std::string& /*table*/, const std::string& winner, int score) {
        std::cout << "[EVENT] Round Ended. Winner: " << winner << " (Score: " << score << ")" << std::endl;
    });

    client.set_on_end_hand([&](const std::string& /*table*/, const std::vector<int>& scores) {
        std::cout << "[EVENT] Hand Ended. Hand scores: ";
        for (auto s : scores) std::cout << s << " ";
        std::cout << std::endl;
    });

    client.set_on_game_over([&](const std::string& /*table*/, const std::vector<int>& final_scores) {
        std::cout << "\n========================================" << std::endl;
        std::cout << "[EVENT] GAME OVER! Final Scores: ";
        for (size_t i = 0; i < final_scores.size(); ++i) {
            if (i < state.players.size()) {
                std::cout << state.players[i] << "=" << final_scores[i] << " ";
            } else {
                std::cout << final_scores[i] << " ";
            }
        }
        std::cout << "\n========================================" << std::endl;
        state.isRunning = false;
    });

    client.set_on_leave([&](const std::string& /*table*/, const std::string& player) {
        std::cout << "[EVENT] Player left table: " << player << std::endl;
        if (player != state.username) {
            std::cout << "Other player left, exiting game..." << std::endl;
            state.isRunning = false;
        }
    });

    // Start authorization flow
    std::cout << "Authorizing user..." << std::endl;
    client.authorize(state.username, state.password, [&](bool success, const std::string& reply) {
        if (!success) {
            std::cerr << "Authorization failed: " << reply << std::endl;
            state.isRunning = false;
            return;
        }

        std::cout << "Authorized! Private channel topic: " << reply << std::endl;

        // Perform matchmaking
        std::cout << "Searching for tables..." << std::endl;
        client.list_tables([&, reply](const std::vector<Table>& tables, const std::string& err) {
            if (!err.empty()) {
                std::cerr << "Error listing tables: " << err << std::endl;
                state.isRunning = false;
                return;
            }

            // Find a table with < 4 players
            std::string targetTable;
            for (const auto& t : tables) {
                if (t.players.size() < 4) {
                    targetTable = t.name;
                    break;
                }
            }

            if (!targetTable.empty()) {
                std::cout << "Joining existing table: " << targetTable << std::endl;
                client.join_table(state.username, reply, targetTable, [&](const std::string& secret, const std::string& joinErr) {
                    if (!joinErr.empty()) {
                        std::cerr << "Failed to join: " << joinErr << std::endl;
                        state.isRunning = false;
                        return;
                    }
                    state.secret = secret;
                    state.activeTable = targetTable;
                    std::cout << "Joined successfully! Secret acquired." << std::endl;
                });
            } else {
                std::cout << "No active tables found. Creating a new one..." << std::endl;
                client.create_table(state.username, reply, [&](const std::string& newTableUuid, const std::string& createErr) {
                    if (!createErr.empty()) {
                        std::cerr << "Failed to create table: " << createErr << std::endl;
                        state.isRunning = false;
                        return;
                    }
                    std::cout << "Table created: " << newTableUuid << ". Joining..." << std::endl;
                    client.join_table(state.username, reply, newTableUuid, [&](const std::string& secret, const std::string& joinErr) {
                        if (!joinErr.empty()) {
                            std::cerr << "Failed to join: " << joinErr << std::endl;
                            state.isRunning = false;
                            return;
                        }
                        state.secret = secret;
                        state.activeTable = newTableUuid;
                        std::cout << "Joined successfully! Secret acquired. Waiting for players..." << std::endl;
                    });
                });
            }
        });
    });

    // Main event loop
    while (state.isRunning) {
        client.update();

        // 1. Handle rule choice
        if (state.isMyRuleChoice && !state.selectableRules.empty()) {
            state.isMyRuleChoice = false;
            Rule chosen = state.selectableRules[0]; // Simple bot strategy: pick first rule
            std::cout << "Choosing game rule: " << rule_to_string(chosen) << std::endl;
            client.choose_rule(state.username, state.secret, chosen, [](bool ok, const std::string& err) {
                if (!ok) std::cerr << "Failed to choose rule: " << err << std::endl;
            });
        }

        // 2. Handle bidding
        if (state.isMyBid) {
            state.isMyBid = false;
            std::cout << "Bidding: 0 (Pass)" << std::endl;
            client.bid(state.username, state.secret, 0, [](bool ok, const std::string& err) {
                if (!ok) std::cerr << "Failed to submit bid: " << err << std::endl;
            });
        }

        // 3. Handle game play
        if (state.isMyTurn && !state.hand.empty()) {
            state.isMyTurn = false;

            // Simple bot play strategy: select first card in hand
            // If the server rejects the play, try the next one
            struct PlayContext {
                std::vector<Card> remainingOptions;
                std::string username;
                std::string secret;
                size_t index = 0;
            };

            auto ctx = std::make_shared<PlayContext>();
            ctx->remainingOptions = state.hand;
            ctx->username = state.username;
            ctx->secret = state.secret;
            
            // Shuffle options to show some variety
            std::shuffle(ctx->remainingOptions.begin(), ctx->remainingOptions.end(), g);

            // Define recursive play attempt function
            std::function<void()> attemptPlay;
            attemptPlay = [ctx, &client, &state, &attemptPlay]() {
                if (ctx->index >= ctx->remainingOptions.size()) {
                    std::cerr << "ERROR: Ran out of card options to play!" << std::endl;
                    return;
                }

                Card choice = ctx->remainingOptions[ctx->index];
                std::cout << "Attempting to play card: " << choice.to_string() << std::endl;

                client.play_card(ctx->username, ctx->secret, choice, [ctx, choice, &state, &attemptPlay](bool ok, const std::string& err) {
                    if (ok) {
                        std::cout << "Successfully played: " << choice.to_string() << std::endl;
                        // Remove the played card from our local hand state
                        auto it = std::find(state.hand.begin(), state.hand.end(), choice);
                        if (it != state.hand.end()) {
                            state.hand.erase(it);
                        }
                    } else {
                        std::cout << "Play rejected (" << err << "). Trying next card..." << std::endl;
                        ctx->index++;
                        attemptPlay();
                    }
                });
            };

            attemptPlay();
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    std::cout << "Agent stopping..." << std::endl;
    if (!state.secret.empty()) {
        client.leave_game(state.username, state.secret, [](bool, const std::string&) {});
        client.update();
    }
    client.disconnect();
    std::cout << "Agent finished." << std::endl;

    return 0;
}
