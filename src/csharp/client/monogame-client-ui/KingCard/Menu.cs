using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace KingCard
{
    class MenuItem
    {
        protected Texture2D _image;
        protected Rectangle _area;
        protected Vector2 position;
        protected Vector2 origin;
        protected int item;
        protected float scale;

        public MenuItem(int val)
        {
            item = val;
            scale = 1f;
        }

        public Texture2D Image
        { 
            get {return _image;}
            set 
            {
                _image = value;
                onImageSet();
            }
        }

        virtual protected void onImageSet()
        {
            origin = new Vector2(_image.Width / 2f, _image.Height / 2f);
        }

        public Vector2 Position
        {
            get {return position;}
            set
            {
                position = value;
                onPositionSet();
            }
        }

        virtual protected void onPositionSet()
        {
            _area = new Rectangle((int)(position.X - origin.X),
                                  (int)(position.Y - origin.Y),
                                  _image.Width, _image.Height);
        }

        virtual public int CheckSelected(Point pos)
        {
            if (_area.Contains(pos))
                return item;
            else
                return Menu.NotSelected;
        }

        virtual public void SetMouseOver(Point pos)
        {
            if (_area.Contains(pos))
                scale = 1.2f;
            else
                scale = 1f;
        }

        virtual public void Draw(SpriteBatch batch)
        {
            if (_image != null)
                batch.Draw(_image, position, null, Color.White, 0f, origin, scale, SpriteEffects.None, 0f);
        }
    }

    class MenuItemTextVisualizer : MenuItem
    {
        static public float velocity = .1f;

        const float offset_X = 15f;
        const float offset_Y = 35f;

        string basetext;
        List<string> splitText;
        bool pressed;
        int lastYPos;
        int topline = 0;

        public MenuItemTextVisualizer(string text)
            : base(Menu.NotSelected)
        {
            pressed = false;
            basetext = text; 
        }

        protected override void onImageSet()
        {
            base.onImageSet();

            float size_x = TextManager.Font.MeasureString("MI").X/2f;

            int chars_line = (int) ((_image.Width - 2f*offset_X) / size_x);
            
            splitText = new List<string>();
            char[] sep1 = { '\n' };
            char[] sep = {' ','\t'};

            string[] lines = basetext.Split(sep1);

            foreach (string line in lines)
            {
                string[] words = line.Split(sep);

                string temp = "";
                foreach (string word in words)
                {
                    temp += word + " ";

                    if (temp.Length >= chars_line)
                    {
                        splitText.Add(temp);
                        temp = "";
                    }
                }
                if( temp.Length > 0 )
                    splitText.Add(temp);

                splitText.Add("");
            }
            
        }

        public override void SetMouseOver(Point pos)
        {
            if (!pressed)
            {
                pressed = true;
                lastYPos = pos.Y;
            }

            topline += (int)((lastYPos - pos.Y) * velocity);
            topline = (int)MathHelper.Clamp(topline, 0f, splitText.Count);
            lastYPos = pos.Y;
        }

        public override int CheckSelected(Point pos)
        {
            pressed = false;

            return Menu.NotSelected;
        }

        public override void Draw(SpriteBatch batch)
        {
            if (_image != null)
            {
                batch.Draw(_image, position, null, Color.White, 0f, origin, scale, SpriteEffects.None, 0f);

                TextManager.Draw(batch, "REGRAS (Arraste para ver mais)", new Vector2(_area.X + _area.Width/2f, _area.Y + 20f ), TextManager.TEXT_ALIGN.CENTER);

                Vector2 pos = new Vector2(_area.X + offset_X, _area.Y + offset_Y);
                float diff = TextManager.Font.MeasureString("M").Y;

                int maxlines = (int) MathHelper.Min(splitText.Count, topline + (int)Math.Floor(((double)_image.Height -2.0*offset_Y) / diff) );

                for (int i = topline; i < maxlines; ++i)
                {
                    TextManager.Draw(batch, splitText[i], pos, TextManager.TEXT_ALIGN.LEFT);
                    pos.Y += diff;
                }
            }
        }
    }

    class Menu
    {
        List<MenuItem> menuItens;

        public const int NotSelected = 0;
        public const int NovoJogo = 1;
        public const int Regras = 2;

        public Menu()
        {
            menuItens = new List<MenuItem>();
        }

        public void AddContent(int item, Texture2D image)
        {
            var mi = new MenuItem(item);
            mi.Image = image;
            menuItens.Add(mi);
        }

        public void AddSpecialContent(MenuItem mi)
        {
            menuItens.Add(mi);
        }

        public void Resize(int w, int h)
        {
            if( menuItens.Count == 0 )
                return;

            float sum = 0f;
            foreach (var mi in menuItens)
                sum += mi.Image.Height;

            float empty = h - sum;

            float pos_x = w/2f;
            float diff = empty/(menuItens.Count+1f);
            float pos_y = 0f;

            foreach (MenuItem mi in menuItens)
            {
                pos_y += diff + mi.Image.Height/2f;
                mi.Position = new Vector2(pos_x, pos_y);
                pos_y += mi.Image.Height/2f;
            }
        }

        public int CheckSelected(Point pos)
        {
            int ret = NotSelected;

            foreach(MenuItem mi in menuItens)
                ret += mi.CheckSelected(pos);

            return ret;
        }

        public void SetMouseOver(Point pos)
        {
            foreach (MenuItem mi in menuItens)
                mi.SetMouseOver(pos);
        }

        public void Reset()
        {
            menuItens.Clear();
        }

        public void Draw(SpriteBatch batch)
        {
            foreach (MenuItem mi in menuItens)
                mi.Draw(batch);
        }
    }
}
