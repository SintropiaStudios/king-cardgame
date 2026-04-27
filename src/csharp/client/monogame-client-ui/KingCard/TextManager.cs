using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace KingCard
{
    class TextManager
    {
        static public SpriteFont Font;

        public enum TEXT_ALIGN
        {
            LEFT = 0,
            CENTER
        }

        static public void Draw(SpriteBatch sp, string text, Vector2 position, TEXT_ALIGN align, float scale=1f, float angle=0f)
        {
            Vector2 origin = new Vector2(0,0);

            if (align == TEXT_ALIGN.CENTER)
            {
                var size = Font.MeasureString(text);
                size *= scale;

                origin = new Vector2( size.X/2, size.Y/2 );
            }

            sp.DrawString(Font, text, position, Color.Black, angle, origin, scale, SpriteEffects.None, 0f);
        }
    }
}
