# KorwenPlus — Copilot Instructions

KorwenPlus is a World of Warcraft addon for **WoW Forever** (the Classic+ branch,
level-60 cap, client build `1.60.1.70374`, TOC `## Interface: 16001`).
It has no build system, package manager, or external libraries — it's plain
Lua/XML loaded directly by the game client per the `.toc` file list.

The addon is intentionally minimal: `main` contains the core initialization
plus a few small features added one at a time. Earlier experiments
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
    missing keys into the character's settings without clobbering existing
    user settings.
  - Per-character settings: `KorwenPlusDB` (the single account-wide
    `SavedVariables` entry) holds `characters["Name - Realm"]`, and `Korwen.db`
    is the current character's table. `Korwen:CopySettingsFrom(key)` copies
    only keys in `Korwen.defaults`.
  - Per-Edit-Mode-layout settings (frame sizes and positions):
    `Korwen:LayoutSettings()` returns `KorwenPlusDB.layouts[name]` for the
    active layout (character layouts prefixed with the character key), filled
    from `Korwen.layoutDefaults`, or nil until Blizzard has loaded layouts.
  - `Korwen:On(event, handler)` — a tiny pub/sub event bus. **All modules
    register events through this, not their own `CreateFrame` +
    `RegisterEvent`.** `Korwen.db` is only populated once `ADDON_LOADED` fires
    for this addon, so any handler that touches `Korwen.db` must not run
    before that.
  - The `/korwenplus` and `/kp` slash commands, which call `Korwen:OpenOptions()`.
- **`Features/Portraits.lua`** — if `portrait3D` is on at login, lays a
  `PlayerModel` over the 2D portrait of Blizzard's player/target/focus/pet
  frames (created lazily on first use, after Blizzard has set frame levels).
  The 2D portrait is only made transparent while the unit is visible, so it
  stays as the fallback for out-of-range units. When the setting is off,
  nothing is registered; changing it takes effect after `/reload`.
- **`Features/TargetOfTarget.lua`** — only active if `totEnabled` is on at
  login. Removes the portrait of Blizzard's
  `TargetFrameToT` (reparented into a hidden frame, since Blizzard resets
  alpha/shown state) and replaces the ring art (`FrameTexture`) with its right
  end mirrored onto the left, sized around the bars. Blizzard's geometry is
  measured once (`measure()`) and `applyWidth()` rebuilds box, bars and name
  from it for the layout's `totWidth` (health bar widened to the left), only
  on first show, width change and layout change. Both bars are stretched past
  a shared span centered in the box and clipped to it with rectangular masks
  (replacing Blizzard's portrait-shaped ones), because the bar art doesn't
  fill its frame and differs per power type.
  While Edit Mode is open (`EventRegistry` callbacks
  `EditMode.Enter`/`EditMode.Exit`), it shows a draggable handle in its place.
  The frame's center is saved as the layout's `totPosition` in UIParent
  coordinates (so `totScale` changes resize it in place); on layout change
  (`EDIT_MODE_LAYOUTS_UPDATED`, hooked `SelectLayout`) it's re-applied, or
  Blizzard's anchor (captured at load) restored. Scale/position
  are applied out of combat only — the frame is protected. Never replace
  `tot.Update`: `TargetFrame:Update()` calls it and then continues, so a
  replacement taints the whole target frame (secret-value errors).
  Optional health/power percentages (`totHealthText`/`totPowerText`) come from
  `UnitHealthPercent`/`UnitPowerPercent` with a 0–100 curve and are passed
  straight into `SetFormattedText` (secret). Since Blizzard updates the ToT
  per frame and `targettarget` gets no unit events, they refresh on a
  `C_Timer` ticker that runs only while the frame is shown.
- **`Core/Options.lua`** — loads last; registers the "KorwenPlus" page under
  Options > AddOns with Blizzard's `Settings` API.
  `addCheckbox(key, label, tooltip, opts)` and
  `addPercentSlider(key, label, tooltip, opts)` bind a control directly to a
  top-level key in `Korwen.db` (default from `Korwen.defaults[key]`) and return
  its initializer. `opts.perLayout` binds to the active Edit Mode layout's
  settings instead (a proxy setting, default from `Korwen.layoutDefaults`).
  `opts.onChange` applies a setting live; prefer
  `opts.requiresReload = true` and applying settings only at load over live
  on/off logic: if any such setting differs from its login value, a
  "Reload UI" popup is shown. The page is split by section headers
  (`addHeader`) into "Character" and "Edit Mode layout" settings; put new
  settings under the header matching where they're stored.
  `enabledBy(child, key)` disables a setting while a checkbox is off.

## Conventions

- **No third-party libraries.** Prefer reusing Blizzard's own frames/functions
  over reimplementing logic.
- **Single `SavedVariables` table**: `KorwenPlusDB`, with the current
  character's settings exposed as `Korwen.db` only after `ADDON_LOADED`. All
  persisted settings go through `Korwen.defaults`/`Korwen.layoutDefaults` and
  `applyDefaults` so upgrades (adding a new default key) don't require a
  migration step. Per-character settings belong in `Korwen.defaults`; frame
  sizes and positions belong per Edit Mode layout (`Korwen.layoutDefaults`).
- **Module files never call `RegisterEvent` directly** — always go through
  `Korwen:On(event, handler)` so handlers for the same event share one real
  `Frame`/`OnEvent` dispatcher.
- **TOC load order matters**: `Core/Init.lua` must load first and
  `Core/Options.lua` last. When adding a new feature file, put it between them
  in `KorwenPlus.toc`.
- Keep each feature in its own file with its own `Korwen.db` settings
  sub-table, independent of other features.
