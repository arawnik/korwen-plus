# KorwenPlus — Copilot Instructions

KorwenPlus is a World of Warcraft addon for **WoW Forever** (the Classic+ branch,
level-60 cap, client build `1.60.1.70374`, TOC `## Interface: 16001`).
It has no build system, package manager, or external libraries — it's plain
Lua/XML loaded directly by the game client per the `.toc` file list.

The addon is intentionally minimal: `main` contains only the core
initialization, and features are added one at a time. Earlier experiments
(custom unit frames, combat text, auto actions, options panel) live on the
`prototype` branch for reference — it is not merged into `main`.

## Git

- **NEVER create git commits** (or amend, rebase, push, or otherwise rewrite
  history). Leave all changes uncommitted in the working tree — the user
  reviews the code and commits it themselves.

## Running / testing

There is no compiler or test runner. "Testing" means:

1. Symlink or copy the `KorwenPlus/` folder into the WoW Forever
   `Interface/AddOns/` directory.
2. `/reload` or relaunch the client.
3. Use `/console scriptErrors 1` to surface Lua errors instead of silent
   failures, or install BugSack/BugGrabber if available.
4. There's no Lua interpreter dependency — but before committing, a quick
   syntax sanity check (e.g. `luaparse` via a throwaway `npm install
   luaparse`, or any standalone Lua install) catches typos the game would
   otherwise only report at runtime via a red error toast.

## Client API notes

- The client is modern-based (old globals like `PlayerFrameHealthBar` are
  `nil`); verify Blizzard frame globals and APIs in-game before relying on them.
- It enforces "secret values": `UnitHealth`/`UnitPower` etc. return secret
  numbers — NEVER do arithmetic/comparison on them. Only pass them untouched
  into widget setters like `StatusBar:SetValue` or
  `FontString:SetFormattedText`. `UnitName`/`UnitLevel`/`UnitClass` are not
  secret.
- Never modify protected/Blizzard frames in combat; queue changes until
  `PLAYER_REGEN_ENABLED`.

## Architecture

- **`Core/Init.lua`** loads first and sets up the shared addon namespace
  (`local ADDON_NAME, Korwen = ...`, every file gets this same `Korwen` table via
  its own `...` vararg — this is the addon-wide "export" mechanism, not a
  global). It also defines:
  - `Korwen.defaults` / `Korwen.applyDefaults(db, defaults)` — recursively fills
    missing keys into `KorwenPlusDB` (the single `SavedVariables` entry)
    without clobbering existing user settings.
  - `Korwen:On(event, handler)` — a tiny pub/sub event bus. **All modules
    register events through this, not their own `CreateFrame` +
    `RegisterEvent`.** `Korwen.db` is only populated once `ADDON_LOADED` fires
    for this addon, so any handler that touches `Korwen.db` must not run
    before that.
  - The `/korwenplus` and `/kp` slash commands, which call `Korwen:OpenOptions()`
    if a module defines it.

## Conventions

- **No third-party libraries.** Prefer reusing Blizzard's own frames/functions
  over reimplementing logic.
- **Single `SavedVariables` table**: `KorwenPlusDB`, exposed as `Korwen.db` only
  after `ADDON_LOADED`. All persisted settings go through
  `Korwen.defaults`/`applyDefaults` so upgrades (adding a new default key)
  don't require a migration step.
- **Module files never call `RegisterEvent` directly** — always go through
  `Korwen:On(event, handler)` so handlers for the same event share one real
  `Frame`/`OnEvent` dispatcher.
- **TOC load order matters**: `Core/Init.lua` must load first. When adding a
  new file, append it to the file list in `KorwenPlus.toc` in the position
  that matches its dependencies.
- Keep each feature in its own file with its own `Korwen.db` settings
  sub-table, independent of other features.
