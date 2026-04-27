using System;
using System.Linq;
using NetMQ.Sockets;
using NetMQ;
using Newtonsoft.Json.Linq;
using Newtonsoft.Json;
using System.ComponentModel;

namespace KingCard
{
    class KingClient
    {
        private RequestSocket action;
        private SubscriberSocket subscription;

        private String _tableName;
        private String _playerName;
        private String _channel;
        private String _secret;

        public Table table;
        public string[] choices;

        private delegate void ProcessDelegate(string msg);
        private ProcessDelegate currentProcess;

        public KingClient(string url)
        {
            _tableName = "";
            _channel = "";

            action = new RequestSocket(url + ":5555");
            
            subscription = new SubscriberSocket(url + ":5556");
            subscription.SubscribeToAnyTopic();
        }

        public string PublishHall(string msg, string args = null)
        {
            string response;
            if (args != null)
            {
                msg += " " + args;
            }

            action.SendFrame(msg);
            response = action.ReceiveFrameString();

            return response;
        }

        public string PublishTable(string req, string args = null)
        {
            string msg = String.Format("{0} {1} {2}", req, _playerName, _secret);
            if (args != null)
            {
                msg += " " + args;
            }
            action.SendFrame(msg);
            return action.ReceiveFrameString();
        }

        public string PollServer(int timeout=1000)
        {
            if (subscription.TryReceiveFrameString(new TimeSpan(0, 0, 0, 0, timeout), out string rsp))
            {
                if (rsp.StartsWith("GAMEOVER"))
                {
                    //GAME IS OVER ...
                    currentProcess = ListTables;
                    return rsp;
                }
                currentProcess(rsp);
            }
            return "";
        }

        public void StartRequestGame()
        {
            StartListTables();
        }

        public void StartListTables()
        {
            string rsp = PublishHall("LIST");
            ListTables(rsp);
        }

        public bool Authorize(string playerName, string password)
        {
            string rsp = PublishHall("AUTHORIZE", String.Format("{0} {1}", playerName, password));
            if (rsp.StartsWith("ERROR"))
            {
                return false;
            }

            _playerName = playerName;
            _channel = rsp;
            return true;
        }

        private void ListTables(string msg)
        {
            dynamic tbl_lst = JsonConvert.DeserializeObject(msg);

            if (msg != "[]")
            {
                _tableName = tbl_lst[0].name;
                JoinTable(_tableName);
            }
            else
            {
                string rsp = PublishHall("TABLE", String.Format("{0} {1}", _playerName, _channel));
                if (rsp.StartsWith("ERROR"))
                {
                    Console.WriteLine("No can create, from 0: " + rsp);
                    currentProcess = ListTables;
                    return;
                }

                rsp = PublishHall("LIST");
                if (rsp.StartsWith("ERROR"))
                {
                    Console.WriteLine("Exhausted All attempts");
                    return;
                }
                ListTables(rsp);
            }
        }

        private void JoinTable(string _tablename)
        {
            subscription.Subscribe(_tablename);

            string rsp = PublishHall("JOIN", String.Format("{0} {1} {2}", _playerName, _channel, _tableName));
            if (rsp.StartsWith("ERROR"))
            {
                Console.WriteLine("No can join, from 0: " + rsp);
                subscription.Unsubscribe(_tablename);
                currentProcess = ListTables;
            }

            _secret = rsp;
            currentProcess = StartGame;
        }

        private void StartGame(string msg)
        {
            string[] order = msg.Split(" ").Skip(2).ToArray();
            if (order.Length < 4)
            {
                Console.WriteLine("Unexpected message pattern: " + msg);
                order = String.Format("{0} B C D", _playerName).Split();
            }

            table = new Table(order, _playerName);

            currentProcess = SetupHand;
        }

        private void SetupHand(string msg)
        {
            string[] startr_choices = msg.Split(" ");
            if (startr_choices.Length > 3)
            {
                choices = startr_choices.Skip(3).ToArray();
            }

            string[] hand = ParseStringList(PublishTable("GETHAND"));
            table.SetupHand(hand);

            if (table.isPlayerTurn())
                currentProcess = ChooseHand;
            else
                currentProcess = DefineHand;
        }

        private void DefineHand(string msg)
        {
            //TODO: Is better to check for error condition
            string[] handRule = msg.Split(" ").Skip(2).ToArray();
            if (handRule.Length == 0)
            {
                Console.WriteLine("Weird Message received " + msg);
                handRule.Append("VAZA");
            }
            table.Hand = handRule[0];
            currentProcess = RoundPlay;
        }

        private void ChooseHand(string msg)
        {
            //TODO: Take user input here
            if (choices == null || choices.Length == 0)
                choices.Append("VAZA");

            PublishTable("GAME", choices[0]);

            currentProcess = DefineHand;
        }

        private void RoundPlay(string msg)
        {
            string[] msg_arr = msg.Split(" ").Skip(1).ToArray();

            if (msg_arr[0] == "ENDHAND")
            {
                int[] score = Enumerable.Select(msg_arr.Skip(1),
                                                x => Int32.Parse(x)).ToArray();
                if (score.Length < 4)
                {
                    Console.WriteLine("Weird ENDHAND: " + msg);
                    while (score.Length < 4) score.Append(0);
                }
                table.EndHand(score);
                currentProcess = SetupHand;
            }
            else if (msg_arr[0] == "ENDROUND" && msg_arr.Length == 3)
            {
                string nextname = msg_arr[1];
                int score = Int32.Parse(msg_arr[2]);

                table.EndRound(nextname, score);
            }
            else if (msg_arr[0] == "PLAY")
            {
                table.PlayCard(msg_arr[1]);
            }
            // I'm not treating the error case ... it would be the else
        }

        static string[] ParseStringList(string str, string begin = "")
        {
            char[] delim = { ',' };
            string[] values = str.Remove(0, begin.Length).
                                  Replace('[', ' ').Replace(']', ' ').Trim().
                                  Split(delim);

            return Enumerable.Select(values,
                                     x => x.Trim().Replace("'", "")).ToArray();
        }

        static int[] ParseIntList(string str, string begin = "")
        {
            char[] delim = { ',' };
            string[] values = str.Remove(0, begin.Length).
                                  Replace('[', ' ').Replace(']', ' ').Trim().
                                  Split(delim);

            return Enumerable.Select(values,
                                     x => Int32.Parse(x)).ToArray();
        }
    }
}
