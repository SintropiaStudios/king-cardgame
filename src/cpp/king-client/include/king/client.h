#pragma once

#include <string>
#include <vector>
#include <functional>
#include <memory>
#include "king/types.h"

namespace king {

class KingClient {
public:
    KingClient();
    ~KingClient();

    // Prevent copying
    KingClient(const KingClient&) = delete;
    KingClient& operator=(const KingClient&) = delete;

    // Connect to server ports
    bool connect(const std::string& host, int req_port = 5555, int sub_port = 5556);
    void disconnect();
    bool is_connected() const;

    // Process all pending network messages and run callbacks on the calling thread.
    // Call this regularly (e.g. once per frame in your game loop).
    void update();

    // --- REQ Commands (Asynchronous with Callback) ---
    void authorize(const std::string& username, const std::string& password,
                   std::function<void(bool success, const std::string& channel_or_error)> cb);

    void list_tables(std::function<void(const std::vector<Table>& tables, const std::string& error)> cb);

    void create_table(const std::string& username, const std::string& channel,
                      std::function<void(const std::string& table_uuid, const std::string& error)> cb);

    void join_table(const std::string& username, const std::string& channel, const std::string& table_uuid,
                    std::function<void(const std::string& player_secret, const std::string& error)> cb);

    void get_hand(const std::string& username, const std::string& secret,
                  std::function<void(const std::vector<Card>& hand, const std::string& error)> cb);

    void get_turn(const std::string& username, const std::string& secret,
                  std::function<void(const std::string& active_player, const std::string& error)> cb);

    void choose_rule(const std::string& username, const std::string& secret, Rule rule,
                     std::function<void(bool success, const std::string& error)> cb);

    void bid(const std::string& username, const std::string& secret, int value,
             std::function<void(bool success, const std::string& error)> cb);

    void decide(const std::string& username, const std::string& secret, bool accept,
                std::function<void(bool success, const std::string& error)> cb);

    void choose_trump(const std::string& username, const std::string& secret, Suit suit,
                      std::function<void(bool success, const std::string& error)> cb);

    void play_card(const std::string& username, const std::string& secret, const Card& card,
                   std::function<void(bool success, const std::string& error)> cb);

    void leave_game(const std::string& username, const std::string& secret,
                    std::function<void(bool success, const std::string& error)> cb);

    void leave_table(const std::string& username, const std::string& secret,
                     std::function<void(bool success, const std::string& error)> cb);

    void list_users(std::function<void(bool success, const std::string& error)> cb);

    void invite_match(const std::string& username, const std::string& channel,
                      const std::string& p2, const std::string& p3, const std::string& p4,
                      std::function<void(const std::string& table_uuid, const std::string& error)> cb);

    // --- Manual PUB/SUB Subscriptions ---
    void subscribe(const std::string& topic);
    void unsubscribe(const std::string& topic);

    // --- PUB/SUB Event Callback Registration ---
    void set_on_game_start(std::function<void(const std::string& table_uuid, const std::vector<std::string>& players)> cb);
    void set_on_hand_start(std::function<void(const std::string& table_uuid, const std::string& starter, const std::vector<Rule>& allowed_rules)> cb);
    void set_on_turn(std::function<void(const std::string& table_uuid, const std::string& player)> cb);
    void set_on_bid_turn(std::function<void(const std::string& table_uuid, const std::string& player)> cb);
    void set_on_bid(std::function<void(const std::string& table_uuid, const std::string& player, int value)> cb);
    void set_on_game_chosen(std::function<void(const std::string& table_uuid, Rule rule, Suit trump)> cb);
    void set_on_card_played(std::function<void(const std::string& table_uuid, const Card& card)> cb);
    void set_on_end_round(std::function<void(const std::string& table_uuid, const std::string& winner, int score)> cb);
    void set_on_end_hand(std::function<void(const std::string& table_uuid, const std::vector<int>& hand_scores)> cb);
    void set_on_game_over(std::function<void(const std::string& table_uuid, const std::vector<int>& final_scores)> cb);
    void set_on_leave(std::function<void(const std::string& table_uuid, const std::string& player)> cb);

    // Private updates
    void set_on_ask_join(std::function<void(const std::string& table_uuid)> cb);
    void set_on_user_list(std::function<void(const std::vector<std::string>& users)> cb);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace king
