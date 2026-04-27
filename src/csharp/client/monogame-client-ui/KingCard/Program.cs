using System;

namespace KingCard
{
    public static class Program
    {
        [STAThread]
        static void Main()
        {
            using (var game = new KingGame())
                game.Run();
        }
    }
}
