# FlyCart

Turns the golf cart into a flying vehicle in Sons of the Forest. The cart seats
up to 4 players.

## Multiplayer

Client side only. Nothing gets installed on a dedicated server. The player
driving needs the mod. Passengers ride the cart as normal.

## Installation

### Easy install

Close the game, open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/JustinOros/sotf-flycart/main/Install.ps1 | iex
```

### Manual install

1. Install [RedLoader](https://github.com/ToniMacaroni/RedLoader/releases/latest)
   and launch the game once
2. Download `FlyCart.zip` from the
   [latest release](https://github.com/JustinOros/sotf-flycart/releases/latest)
3. Extract it into the `Mods` folder inside your game folder

```
Mods\FlyCart.dll
Mods\FlyCart\manifest.json
```

## Usage

Sit in the driver seat of a golf cart and press Space to take off. Leave the
cart or hold Left Ctrl near the ground to land.

| Key | Action |
| --- | --- |
| W / S | Forward / back |
| A / D | Turn |
| Space | Take off, then up |
| Left Ctrl | Down, and land when near the ground |

| Command | Action |
| --- | --- |
| `flycart on` | Enable Space takeoff (on by default) |
| `flycart off` | Land and disable Space takeoff |
| `flycartspeed 22 10 70` | Set forward speed, climb speed and turn rate |
| `flycartdump` | Write the cart's objects and components to `UserData\FlyCartDump.txt` |

## Building from source

```powershell
.\build.ps1 -Install
```

Use `-Package` to build `FlyCart.zip` for a release.

## Troubleshooting

Check `_RedLoader\Latest.log` in your game folder. If flight does not start,
run `flycartdump` while sitting in the cart and include it with the log when
reporting the problem.
