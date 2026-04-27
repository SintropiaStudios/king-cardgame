using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace KingCard
{
    class Player : IPlayer
    {
        List<Card> hand;
        Rectangle area;
        string _name;
        int lastscore;
        int score;

        public string Name
        {
            get { return _name; }
            set { _name = value; }
        }

        public Rectangle Area
        {
            get { return area; }
        }

        public int LastScore
        {
            get { return lastscore; }
            set { lastscore = value; }
        }

        public int Score
        {
            get { return score; }
            set { score = value; }
        }

        public Player(string name)
        {
            _name = name;
            hand = new List<Card>();
            area = new Rectangle();
            lastscore = 0;
        }

        public int CardCount()
        {
            return hand.Count;
        }

        public void PlayCard(string card)
        {
            hand.Remove(new Card(card));
        }

        public void SetHand(string[] cards)
        {
            hand.Clear();
            foreach( string c in cards)
                hand.Add(new Card(c));
        }

        public IEnumerator<Card> GetEnumerator()
        {
            return hand.GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator) GetEnumerator();
        }

        public void Resize(int w, int h)
        {
            area.X = (int)(0.1f * w);
            area.Y = h - (int)(1.1f * Card.card_y_size);
            area.Width = w - 2 * area.X;
            area.Height = h - area.Y;
        }

        public Vector2 getIncrement()
        {
            return new Vector2(area.Width / (hand.Count + 1), 0f);
        }

        public Vector2 getStartPos()
        {
            return new Vector2(area.X + Card.card_x_size / 2,
                               area.Y + area.Height / 2f);
        }

        public Vector2 getNamePos()
        {
            return new Vector2(area.Center.X, area.Y-0.2f*(area.Height));
        }
        
        public float getNameAngle()
        {
            return 0f;
        }
    }
}
