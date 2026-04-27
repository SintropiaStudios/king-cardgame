# C# Implementation

The C# implementation provides a modern graphical client built with **MonoGame** and **NetMQ** (a native C# ZeroMQ implementation).

## 🎮 MonoGame Client

Located in `src/csharp/client/`, this client offers a 2D graphical experience.

### Requirements
- **.NET SDK**
- **MonoGame Framework**
- **NetMQ** and **Newtonsoft.Json** (managed via NuGet)

### Build and Run

You can open the `monogame-client.sln` solution in Visual Studio or use the dotnet CLI:

```bash
cd src/csharp/client
dotnet build monogame-client.sln
dotnet run --project monogame-client-ui/KingCard.csproj
```

## 📂 Structure
- `monogame-client-ui/`: The main application source code.
- `monogame-client-ui/Content/`: Assets like card sprites and fonts, managed by the MonoGame Content Pipeline.
