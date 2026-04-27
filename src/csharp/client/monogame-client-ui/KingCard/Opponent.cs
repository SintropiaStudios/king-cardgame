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
    class FakeHand : IEnumerator<Card>
    {

        Card _back = new Card("");
        int maxcounter;
        int counter;

        public FakeHand(int count, float angle)
        {
            maxcounter = counter;
            counter = count;
            _back.Angle = angle;
        }

        public Card Current
        {
            get { return _back; }
        }

        object IEnumerator.Current
        {
            get { return Current; }
        }

        public bool MoveNext()
        {
            return (counter--) > 0;
        }

        public void Reset()
        {
            counter = maxcounter;
        }

        public void Dispose()
        {
        }
    }

    abstract class BaseOpponent : IPlayer
    {
        protected int numCards;
        protected string _name;
        protected Rectangle area;
        protected int lastscore;
        protected int score;

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

        public BaseOpponent(string name)
        {
            _name = name;
            area = new Rectangle();
            SetHand(null);
        }

        public void SetHand(string[] cards)
        {
            numCards = 13;
        }

        public int CardCount()
        {
            return numCards;
        }

        public void PlayCard(string card)
        {
            numCards--;
        }

        public abstract IEnumerator<Card> GetEnumerator();
        public abstract void Resize(int w, int h);
        public abstract Vector2 getIncrement();
        public abstract Vector2 getStartPos();
        public abstract Vector2 getNamePos();

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator) GetEnumerator();
        }

        public virtual float getNameAngle()
        {
            return 0f;
        }
    }

    class LeftOpponent : BaseOpponent
    {
        public LeftOpponent(string name)
            : base(name)
        {
        }

        public override IEnumerator<Card> GetEnumerator()
        {
            return new FakeHand(numCards, (float)Math.PI/2f);
        }

        public override Vector2 getIncrement()
        {
            return new Vector2(0f, area.Height / (numCards + 1));
        }

        public override Vector2 getStartPos()
        {
            return new Vector2(area.X + area.Width/2,
                               area.Y);
        }

        public override void Resize(int w, int h)
        {
            area.X = (int)(0.05f * Card.card_y_size);
            area.Y = (int)(0.15 * h);
            area.Width = (int)(1.05f * Card.card_y_size);
            area.Height = h - 2*area.Y;
        }

        public override Vector2 getNamePos()
        {
            return new Vector2(area.X + 1.1f*area.Width, (area.Y + area.Height)/2f);
        }

        public override float getNameAngle()
        {
            return (float) Math.PI/2f;
        }
    }

    class RightOpponent : BaseOpponent
    {
        public RightOpponent(string name)
            : base(name)
        {
        }

        public override IEnumerator<Card> GetEnumerator()
        {
            return new FakeHand(numCards, -(float)Math.PI / 2f);
        }

        public override Vector2 getIncrement()
        {
            return new Vector2(0f, area.Height / (numCards + 1));
        }

        public override Vector2 getStartPos()
        {
            return new Vector2(area.X + area.Width / 2,
                               area.Y);
        }

        public override void Resize(int w, int h)
        {
            area.X = w - (int)(1.1f * Card.card_y_size);
            area.Y = (int)(0.15 * h);
            area.Width = w - area.X;
            area.Height = h - 2 * area.Y;
        }

        public override Vector2 getNamePos()
        {
            return new Vector2(area.X - .1f*area.Width, (area.Y + area.Height) / 2f);
        }

        public override float getNameAngle()
        {
            return (float)-Math.PI / 2f;
        }
    }

    class TopOpponent : BaseOpponent
    {
        public TopOpponent(string name)
            : base(name)
        {
        }

        public override IEnumerator<Card> GetEnumerator()
        {
            return new FakeHand(numCards, (float)Math.PI);
        }

        public override Vector2 getIncrement()
        {
            return new Vector2(area.Width / (numCards + 1), 0f);
        }

        public override Vector2 getStartPos()
        {
            return new Vector2(area.X + Card.card_x_size / 2,
                               area.Y + area.Height / 2);
        }

        public override void Resize(int w, int h)
        {
            area.X = (int)(0.2f * w);
            area.Y = (int)(0.05f * Card.card_y_size);
            area.Width = w - 2 * area.X;
            area.Height = (int)(1.05f * Card.card_y_size);
        }

        public override Vector2 getNamePos()
        {
            return new Vector2(area.Center.X, 1.2f * area.Height);
        }
    }
}
