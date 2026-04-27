using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace KingCard
{
    public class KingGame : Game
    {
        #region Delegates for State Machines (Message Processing and Game State)
        public delegate void DrawingDelegate(GameTime time);
        public delegate void UpdateDelegate(GameTime time);
        public Tuple<DrawingDelegate, UpdateDelegate> gameState;
        #endregion

        #region MonoGame Objects and Game Resources
        GraphicsDeviceManager _graphics;
        SpriteBatch _spriteBatch;

        // Game Resources
        KingClient _client;
        Menu _menu;

        int elapsedTime = 0;
        bool lbutton_pressed = false;

        // TODO: Must get from user input!!!
        string player_name = "CSharp";
        string password = "A";
        #endregion

        public KingGame()
        {            
            _graphics = new GraphicsDeviceManager(this);
#if WIN7
            _graphics.IsFullScreen = true;
#endif

            Content.RootDirectory = "Content";

            // Enable the default mouse view
            IsMouseVisible = true;
        }

        protected override void Initialize()
        {
            // TODO: Add your initialization logic here
            var lst = _graphics.GraphicsDevice.Adapter.SupportedDisplayModes;
            _graphics.PreferredBackBufferWidth = 1920;
            _graphics.PreferredBackBufferHeight = 1080;
            _graphics.ApplyChanges();

            base.Initialize();
        }

        protected override void LoadContent()
        {
            _spriteBatch = new SpriteBatch(GraphicsDevice);
            _menu = new Menu();

            try
            {
                Card.deck = Content.Load<Texture2D>("cards");
                Table._background = Content.Load<Texture2D>("back");
                Table._dealertex = Content.Load<Texture2D>("dealer");
                TextManager.Font = Content.Load<SpriteFont>("MenuFont");

                _menu.AddContent(Menu.NovoJogo, Content.Load<Texture2D>("MenuNew"));
                _menu.AddContent(Menu.Regras, Content.Load<Texture2D>("MenuRules"));
            }
            catch (Exception e)
            {
                // Stop the game ... cannot load resources
                //TODO: Debug this shit!
                string s = e.Message;
            }
            // Establish the Menu as the first gamestate
            gameState = new Tuple<DrawingDelegate, UpdateDelegate>(GameMenuDraw, GameMenuUpdate);
        }

        protected override void Update(GameTime gameTime)
        {
            if (GamePad.GetState(PlayerIndex.One).Buttons.Back == ButtonState.Pressed || Keyboard.GetState().IsKeyDown(Keys.Escape))
                Exit();

            // TODO: Add your update logic here
            if (gameState != null)
                gameState.Item2(gameTime);

            base.Update(gameTime);
        }

        protected override void Draw(GameTime gameTime)
        {
            GraphicsDevice.Clear(Color.CornflowerBlue);

            _spriteBatch.Begin();

            if (gameState != null)
                gameState.Item1(gameTime);

            _spriteBatch.End();

            base.Draw(gameTime);
        }


        protected void GameRunningDraw(GameTime time)
        {
            int _width = GraphicsDevice.PresentationParameters.BackBufferWidth;
            int _height = GraphicsDevice.PresentationParameters.BackBufferHeight;

            if (_client.table == null)
            {
                TextManager.Draw(_spriteBatch, "Aguarde, carregando a mesa",
                                new Vector2(_width / 2f, _height / 2f),
                                TextManager.TEXT_ALIGN.CENTER);
                return;
            }

            _client.table.Resize(_width, _height);
            _client.table.Draw(_spriteBatch);
        }

        protected void GameRunningUpdate(GameTime time)
        {
            //TODO: Redesign this Update Loop ... 
            // I need to wait after each card played
            TimeSpan e = time.ElapsedGameTime;
            elapsedTime += e.Milliseconds;

            if (elapsedTime > 1000)
            {
                //TODO Extend this part to get other user's input
                // Like selection of Table, Hand, Positive Auction and Trump
                if ((_client.table != null) && (_client.table.isPlayerTurn()))
                {
                    var st = Mouse.GetState();
                    Card sel = null;

                    if (lbutton_pressed && (st.LeftButton == ButtonState.Released))
                    {
                        sel = _client.table.GetClicked(new Point(st.X, st.Y));
                        lbutton_pressed = false;
                    }
                    else if (st.LeftButton == ButtonState.Pressed)
                    {
                        _client.table.SetMouseOver(new Point(st.X, st.Y));
                        lbutton_pressed = true;
                    }

                    if (sel == null)
                        return;

                    _client.PublishTable("PLAY", sel.ToString());
                }

                elapsedTime = 0;
            } 
            else
            {
                try
                {
                    _client.PollServer(10);
                }
                //TODO Provide a more clear exception handle
                catch (Exception ex)
                {
                    //TODO Handle trouble here
                    string s = ex.Message;
                }
            }
        }

        protected void GameMenuDraw(GameTime time)
        {
            int _width = GraphicsDevice.PresentationParameters.BackBufferWidth;
            int _height = GraphicsDevice.PresentationParameters.BackBufferHeight;

            _menu.Resize(_width, _height);
            _menu.Draw(_spriteBatch);
        }

        protected void GameMenuUpdate(GameTime time)
        {
            MouseState st = Mouse.GetState();

            if (lbutton_pressed)
            {
                // If button alreay pressed check for release
                if (st.LeftButton == ButtonState.Released)
                {
                    lbutton_pressed = false;
                    int item = _menu.CheckSelected(new Point(st.X, st.Y));
                    switch (item)
                    {
                        case Menu.NovoJogo:
                            StartGameServer(true);
                            gameState = new Tuple<DrawingDelegate, UpdateDelegate>(GameRunningDraw, GameRunningUpdate);
                            break;
                        case Menu.Regras:
                            var mi = new MenuItemTextVisualizer(king_rules);
                            mi.Image = Content.Load<Texture2D>("TextVisualizer");
                            _menu.Reset();
                            _menu.AddSpecialContent(mi);
                            _menu.AddContent(Menu.NovoJogo, Content.Load<Texture2D>("MenuNew"));
                            break;
                        default:
                            break;
                    }
                }
                // If not released, then mouse hover on menu
                else
                    _menu.SetMouseOver(new Point(st.X, st.Y));
            }
            //Otherwise check if it has been pressed right now
            else
                lbutton_pressed = (st.LeftButton == ButtonState.Pressed);
        }

        /// <summary>
        /// This is called at the startup, to initialize the connection to Server
        /// </summary>
        /// <param name="SinglePlayer">Wich form of game will be played?</param>
        private void StartGameServer(bool SinglePlayer)
        {
            elapsedTime = 0;
            _client = new KingClient("tcp://localhost");
            if (!_client.Authorize(player_name, password))
                return;

            if (SinglePlayer)
            {
                _client.StartRequestGame();
            }
            else
            {
                _client.StartListTables();
            }
        }

        #region King Rules
        // Oh bullshit ... maybe some easy Rss feeder here would help
        static string king_rules = "Decide-se o primeiro jogador a dar as cartas, atraves de sorteio.\n"
                                   + "A hierarquia das cartas, em ordem decrescente, eh : As, Rei, Dama, Valete, 10 ... ate 2.\n"
                                   + "O jogo desenrola-se sempre pela esquerda, iniciando-se pelo carteador, e ganha a rodada quem jogar a carta mais alta do primeiro naipe jogado nessa rodada, ou o maior trunfo jogado, se tiver sido declarado um trunfo na mao. Sao 13 as rodadas possiveis em cada mao.\n"
                                   + "As cartas sao distribuidas totalmente, uma a uma.\n"
                                   + "Jogo Individual\n"
                                   + "Tambem conhecido como 'King Ind', eh um jogo individual e cada partida eh composta por seis maos ou jogadas negativas e quatro positivas. A contagem dos pontos pode ser feita apenas somando os pontos de cada jogador, sem discriminar em duas colunas. No final quem tiver o melhor saldo positivo sera o ganhador.\n"
                                   + "Maos\nA soma dos pontos atribuidos aos jogadores nas seis maos negativas totaliza -1300. A soma dos pontos atribuidos aos jogadores nas quatro maos positivas totaliza +1300. No fim do jogo a soma dos pontos dos jogadores deve ser zero.\n"
                                   + "Maos negativas\n"
                                   + "- Vaza: O jogador que distribuiu as cartas joga uma carta qualquer, aberta. Todos os demais deverao servir aquele naipe, soh podendo descartar uma carta de outro naipe qualquer se nao tiver o naipe jogado. Quem ganhar uma rodada dara inicio a seguinte. No final, cada participante devera contar e anunciar, para marcacao, quantas rodadas fez. Cada rodada vale 20 pontos negativos. Para efeito de conferencia, o total desta jogada deve dar 260 pontos.\n"
                                   + "- Copas: O objetivo eh nao receber rodadas que contenham cartas de Copas. Regra importante: eh proibido iniciar uma vaza com carta de Copas, tendo qualquer outro naipe na mao. Quem nao tiver condicoes de acompanhar o naipe jogado, podera descartar Copas ou carta de qualquer outro naipe, que considere mais perigoso. No final, contam-se as cartas de Copas recebidas por cada jogador. Cada carta de Copas vale 20 pontos negativos. O total de pontos da rodada eh 260.\n"
                                   + "- Mulheres: Para cada Dama recolhida, o jogador perdera 50 pontos. O total da mao eh 200 pontos. Esta mao tambem eh conhecida como 'Damas'.\n"
                                   + "- Homens: O objetivo eh nao ganhar vazas que contenham Reis ou Valetes. Cada uma destas cartas vale 30 pontos negativos e o total de pontos da mao eh 240. Esta mao tambem eh conhecida como 'Reis ou Valetes'.\n"
                                   + "- King: Quem receber o Rei de Copas em uma rodada, perdera 160 pontos. Importante: Nenhum jogador podera iniciar rodada com Copas, enquanto tiver carta de qualquer outro naipe. O jogador que possuir o Rei de Copas eh obrigado a joga-lo na primeira oportunidade, seja, na primeira vez que nao possa acompanhar o naipe puxado, seja na primeira puxada de copas.\n"
                                   + "- Duas Ultimas: O objectivo eh nao fazer as duas ultimas rodadas, como o proprio nome da jogada esta indicando. Para cada uma das ultimas rodadas feita, o jogador marca 90 pontos negativos, totalizando 180 pontos na mao.\n"
                                   + "O total de pontos negativos dos quatro jogadores devera somar 1.300.";
        #endregion
    }
}
