using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace KingCard
{
    class Card
    {
        // Useful constants for Card Drawing
        public const int card_x_size = 79;
        public const int card_y_size = 123;
        const int back_card_x = card_x_size * 2;
        const int back_card_y = card_y_size * 4;

        // Well ... these ones I cannot made constants ... but they are!
        static readonly public string[] ranks = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K" };
        static readonly public string[] suits = { "C", "D", "H", "S" };

        // Static Texture representing Deck ...
        static public Texture2D deck;

        // Instance Values
        string card;
        Rectangle deck_pos;
        Vector2 position;
        Vector2 origin;
        float angle;
        Vector2 offset;

        //Accessors
        public Vector2 Position
        {
            get { return position; }
            set { position = value; }
        }

        public float Angle
        {
            get { return angle; }
            set { angle = value; }
        }

        // Use empty value to define a back oriented card
        public Card(string value)
        {
            card = value.Trim('\"');
            position = new Vector2(0, 0);
            origin = new Vector2(card_x_size / 2, card_y_size / 2);
            angle = 0f;
            offset = new Vector2(0,0);
            //TODO: Check if its a valid combination of Value and suit
            if (card.Length != 2)
                deck_pos = new Rectangle(back_card_x, back_card_y,
                                         card_x_size,card_y_size);
            else
                deck_pos = new Rectangle(card_x_size * Array.IndexOf(ranks, card.Substring(0, 1)),
                                         card_y_size * Array.IndexOf(suits, card.Substring(1)),
                                         card_x_size, card_y_size);
        }

        public void Draw(SpriteBatch batch)
        {
            batch.Draw(deck, position+offset, deck_pos, Color.White,
                       angle, origin, 1f, SpriteEffects.None, 0f);
        }

        public void SetMouseOver(bool val)
        {
            if (val)
                offset.Y = -(.3f*card_y_size);
            else
                offset.Y = 0f;
        }

        // Object overloaded methods

        public override bool Equals(object obj)
        {
            return  obj != null &&
                    (obj as Card) != null &&
                    (obj as Card).card == card;
        }

        public override int GetHashCode()
        {
            return card.GetHashCode();
        }

        public override string ToString()
        {
            return card;
        }

        //Helper function to sort card arrays

        public static int comnpare(string c1, string c2)
        {
            // First find the relative value of the card 
            // ((x+12)%13 is to rotate de Ace)
            var val1 = (Array.IndexOf(ranks, c1.Substring(0, c1.Length - 1)) + 12) % 13;
            var val2 = (Array.IndexOf(ranks, c2.Substring(0, c2.Length - 1)) + 12) % 13;

            // This *100 is to group the suits and then sort the values
            return (c1[c1.Length-1] - c2[c2.Length-1])*100 + (val1 - val2);
        }
    }
}
