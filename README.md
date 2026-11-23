# Forever Dungeon Map

A dungeon map for WoW Forever (client 1.60.1, interface 16001).

## Install

Copy the `ForeverDungeonMap` folder into
`World of Warcraft\_forever_\Interface\AddOns\` and restart the game.

## What it does

- Press **M** inside a dungeon or raid and the world map opens on that dungeon's map, on the floor you are on.
- Multi-floor dungeons use the normal floor dropdown. The map follows you to another floor when the room name tells it where you are.
- Boss markers are numbered skulls. A defeated boss turns grey and gets a check mark. Click a boss to open it in the Adventure Guide.
- A boss list in the map's bottom-left corner shows defeated bosses and the room you are in.
- **Ctrl+Left-click** on the map marks the room you are standing in. After that, a "You are here" dot appears whenever you are in that room. A boss you kill in a marked room gets a marker there, so maps the game has no boss data for fill in as you play.
- The list of defeated bosses resets when you reset instances, enter another dungeon, or stay out of the dungeon for more than an hour.

## Limits

The Forever client gives addons no position inside instances, so no addon can draw a live arrow there. The "You are here" dot shows the room you are in, using the rooms you marked.

If the game has no map art for an instance, there is nothing to show. If the addon picks the wrong map, open the right one with `/dmap show <name>` and type `/dmap bind`.

## Commands

`/dmap help` lists all commands. The main ones are:

| Command | What it does |
| --- | --- |
| `/dmap` | Open the map of the dungeon you are in |
| `/dmap show <name or ID>` | Open any dungeon map |
| `/dmap list [name]` | List the dungeon maps in the client |
| `/dmap bind` / `unbind` | Set or clear the map used for this instance |
| `/dmap auto` | Turn opening the dungeon map on M on or off |
| `/dmap panel` / `pins` | Show or hide the boss list or the boss markers |
| `/dmap reset` | Clear the defeated bosses |
| `/dmap forget` | Forget the rooms marked on the map shown now |
| `/dmap debug` | Show what the addon detects |
