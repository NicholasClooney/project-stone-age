# Where things live in the game scene

`client/scripts/game.gd` (`class_name GameScene`) is the root of `scenes/main.tscn`. It owns every piece of client state and wires the parts together; the behaviour sits in helpers under `client/scripts/game/`, one per area.

## Pattern

- Each helper is a `RefCounted` with `var game: GameScene`, created first thing in the game's `_init` (before the link can deliver a message).
- Helpers keep no state of their own. They read and write the game's variables through `game.` (for example `game.cell`, `game.music`), and reach consts, statics and the inner `PackWaiter` class through `GameScene.`.
- Every function another script, a test or the game itself calls by name keeps a one-line forwarder at the end of `game.gd`, so `world.text(...)`, `game.load_area_id(...)` and the rest work as before. A function only called inside its helper has no forwarder.
- The engine callbacks stay on the game node (`_input`, `_unhandled_input`, `_physics_process`, `_ready`, `_exit_tree`) so Godot's event and frame order is unchanged; the first three hand off to `game_input.gd` and `game_movement.gd`.
- Per-cell hot paths stay on the game: `project`, `unproject`, `texture`, `character_frame`, `is_walkable`, `can_step`. Drawing and route searches call them for every cell, so they avoid the extra call.

## Helpers

| File | What it does |
| --- | --- |
| `game_remote.gd` | Remote play: backend address, disconnect overlay, reconnect summary, mirroring another device's walk, dispatching backend messages and automation events |
| `game_audio.gd` | Music and effect players, map and battle music, UI and battle sounds, the music and effect switches |
| `game_device.gd` | This device's choices in `viewer.cfg`: zoom, 瞬移模式, battle speed, sound settings, window states |
| `game_automation.gd` | Automation settings from the profile and their batched sending, reopening windows after a reload, whether minimized automation runs, the clone squad switch |
| `game_panels.gd` | Redrawing open panels for new data: throttling while automation runs, keeping scroll places, not rebuilding under typed text |
| `game_battle.gd` | Starting battles, presenting what the backend opened, resolved and closed, sending commands, the web packs a battle needs |
| `game_startup.gd` | Web startup: waiting screen, index, core and start-area downloads, startup errors, `window.stoneAge` and `window.stoneAgeDev` |
| `game_ui.gd` | Building the UI layer and windows (no toolbar: one 游戏助手 button opens `scripts/helper_menu.gd`), the per-map UI, dialogue box, adventure hint, and the shared `text`, `button`, `box` helpers |
| `game_menus.gd` | The villager and merchant, dialogue, and the adventure menu's open, close and actions |
| `game_areas.gd` | Building the world for a map, loading another map, the fade, exits and arrival rules (including field encounters), startup placement, developer map shortcuts |
| `game_input.gd` | Key bindings and rebinding (`scripts/shortcuts.gd`), held movement keys, per-window Esc and keys, clicks and the wheel on the field |
| `game_movement.gd` | Steps, routes, walking to the villager, 瞬移, reset to the square, and the per-frame step (`step_frame`) |
| `game_character.gd` | Changing the character, the pet that follows it, riding and the developer ride toggle |

What stays in `game.gd`: the state declarations, `_init` and `_ready` (the startup order), saving (`checkpoint`, `backup_save`, `release_pets`, `load_profile`, `sync_state`), closing and screenshots, the hot per-cell functions above, and the forwarders.

## Adding code

Put new behaviour in the helper for its area and new state on the game. Add a forwarder only when something outside the helper calls the function by name. A new helper follows the same shape and is preloaded and created at the top of `_init`.
