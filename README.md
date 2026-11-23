# Forever Dungeon Map

A dungeon map for WoW Forever (client 1.60.1, interface 16001).

## Install

1. Download this repo (Code > Download ZIP) and unzip it.
2. Rename the folder to exactly `ForeverDungeonMap`.
3. Put it in `World of Warcraft\_forever_\Interface\AddOns\`, so the file `AddOns\ForeverDungeonMap\ForeverDungeonMap.toc` exists.
4. Restart the game, click **AddOns** at character select and check **Forever Dungeon Map**.

## Use

Press **M** inside a dungeon or raid. The dungeon map opens over the world map, with two tabs:

- **Live** shows your position: the game's own minimap, enlarged, with your arrow, your group and the walls around you. Scroll to zoom. It works in every dungeon, including Forever's new ones.
- **Full map** shows the whole dungeon, from the classic map art that comes with the game. Use `<` and `>` for other floors. **Ctrl+Left-click** where you are to mark the room you are in. A yellow dot then shows you there whenever you are in that room, and the map switches to that floor by itself. **Ctrl+Right-click** forgets the room.

The bosses of the run (from the lockout, and every boss you kill) are listed in the top right corner, with defeated ones greyed out.

The X in the corner shows the normal world map underneath. `/dmap` opens the window anywhere, and `/dmap show <name>` shows any dungeon's map.

## Why the full map has no live arrow

The game gives addons no position inside dungeons, and Forever has no built-in dungeon maps to place you on. The minimap is the one thing the game draws with your real position, so the Live tab shows it.

## Commands

`/dmap help` lists every command. `/dmap debug` shows what the addon detects, which helps when something is missing.
