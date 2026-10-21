# KorwenPlus

WoW Forever addon to make WoW work better for my own preferences.

KorwenPlus is a small, dependency-free addon for **WoW Forever** (the Classic+
branch, level-60 cap, `## Interface: 16001`). It is plain Lua loaded directly
by the game client — no libraries, no build step.

> **Status:** early and intentionally minimal. Features are added one at a time.

## Installation

1. Download or clone this repository.
2. Copy (or symlink) the `KorwenPlus` folder into your WoW Forever
   `Interface/AddOns/` directory, so the path is
   `Interface/AddOns/KorwenPlus/KorwenPlus.toc`.
3. Launch the game (or `/reload`) and make sure **KorwenPlus** is enabled in
   the AddOns list on the character select screen.

## Features

- **3D portraits** — replaces the flat portraits on the player, target, focus
  and pet frames with animated 3D models. Off by default; requires a UI reload
  after changing (you'll be prompted).

## Usage

Settings are under **Options → AddOns → KorwenPlus**.

| Command | Description |
| --- | --- |
| `/korwenplus`, `/kp` | Opens the KorwenPlus settings page. |

Settings are saved per account in the `KorwenPlusDB` saved variable.

## Development

- `KorwenPlus/Core/Init.lua` sets up the shared addon namespace, saved-variable
  defaults, a small event bus (`Korwen:On(event, handler)`), and slash commands.
- New features go in their own file under `Features/` and are added to
  `KorwenPlus.toc` between `Core\Init.lua` and `Core\Options.lua`.
- Enable `/console scriptErrors 1` in-game to see Lua errors while testing.

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for
more detailed architecture notes and conventions.

## License

No license has been chosen yet; all rights reserved by the author.
