# Backend interface (proposal)

Status: draft for review, 2026-09-27. Nothing here is implemented. It refines [architecture](architecture-overview.md), [networking](networking.md) and [local sessions](local-server.md) for one goal: the game is a backend-driven simulation, and every client (desktop window, Vision Pro Safari) only sends configuration/commands and presents state.

## Goals and non-goals

- Battle rules, encounters, automation (auto battle, capture, pet training, hunt scanning, find-pet workflow) and saves run in the backend.
- The desktop build keeps working at every migration step, through an in-process link.
- The same messages later travel over WebSocket to a headless backend on the MacBook.
- Automation keeps running with no client attached.
- Not in scope: multiple players, accounts, public hosting, legacy protocol, movement validation (see [Movement](#movement)).

## Current coupling (measured)

| Finding | Where | Consequence |
| --- | --- | --- |
| UI calls authority synchronously and reads return values | 12 scripts; 39 `session.snapshot()` and 28 `battle_session.snapshot()` calls | Every call site moves to "send command, render latest state" |
| Battle submit is four calls, not one | `game.gd:351-357` (`set_pet_target`, `set_pet_skill`, `set_pet_command`, `submit_action`) | Merge into one atomic command |
| Reward summary is computed by diffing profiles in the client | `game.gd:358-379` | Backend emits the summary in `battle_ended` |
| Encounter RNG and rolls live in the client | `game.gd` `encounter_catalog.step/roll`, `encounter_rng` | Move to backend |
| Gameplay depends on client art presence | `battle_view.can_render_troop` in `game.gd`, `pet_hunt_menu.gd:146,246` | Backend decides from a content manifest |
| Automation loops run in client `_process` and wait for animation | `training_helper.gd:235-307`, `pet_workflow.gd:83-125`, `pet_hunt_menu.gd:216-260` | Move loops to backend runners |
| Private and constant access from UI | `session._pending` (`dev_gm_menu.gd:112`), `session.PET_CAPACITY` (5 sites) | Expose through snapshot |
| Client chooses battle RNG seed and battle class | `game.gd:337-338` | Backend owns both |

## Shape

```text
client scripts ──► ClientLink.send(command) ──► Backend.handle(command)
      ▲                                              │
      └──── ClientState ◄── link.message(event) ◄────┘
```

- `Backend` (`client/server/backend.gd`, a Node so it can tick): owns `GameSession`, the active battle session, `EncounterCatalog` and its RNG, automation runners and the save path. It never touches scene nodes, textures or audio.
- `ClientLink` interface: `send(command: Dictionary) -> int` returns the sequence number; signal `message(event: Dictionary)`.
  - `LocalLink`: in-process. Deep-copies both directions and delivers events on the next frame, so the client never relies on synchronous results. Tests call `flush()` for deterministic delivery.
  - `WebSocketLink`: later. JSON over `WebSocketPeer`; same dictionaries.
- `ClientState` (client side): holds the latest snapshot, battle state and automation status; emits `changed`. UI reads only from here.

## Envelope

All values are JSON-safe: ints, floats, strings, bools, arrays, dictionaries. No `Vector2i`, resources or objects; cells are `[x, y]`. The codec runs the existing `_normalize_numbers` rule on receive, because Godot JSON returns floats.

```gdscript
# client → backend
{"v": 1, "seq": 17, "type": "battle_command", ...fields}
# backend → client
{"v": 1, "type": "rejected", "seq": 17, "reason": "宠物栏已满"}
{"v": 1, "type": "profile", "rev": 204, "profile": {...}}
```

- `seq` is per connection and increasing. Every command gets exactly one `ack` or `rejected`, replacing `session.last_error`.
- `rev` increases on every accepted state change. A client that sees a gap asks for `snapshot`.
- Non-repeatable commands (buy, sell, battle action) are deduplicated by `seq` within a connection.

## Commands

### Session

| Command | Fields | Notes |
| --- | --- | --- |
| `hello` | `protocol`, `client_kind` | Reply is a full `snapshot`. A newer connection takes control; the older one receives `superseded`. |
| `snapshot` | none | Resync after a `rev` gap or reconnect |
| `set_options` | `experience_multiplier`, `clone_squad` | Replaces direct property writes |

### World

| Command | Fields | Replaces |
| --- | --- | --- |
| `report_position` | `map`, `cell` | `set_location`; also the automation position check |
| `field_step` | `map`, `cell` | `encounter_catalog.step` + `begin_wild_battle`; backend may reply with `battle_started` |
| `start_boss_battle` | none | `begin_battle(true)` after `can_fight_boss` |
| `start_debug_battle` | `species`, `enemy_count` | `begin_battle(false, n)` (dev only) |

### Battle

| Command | Fields | Replaces |
| --- | --- | --- |
| `battle_command` | `battle_id`, `action`, `target`, `pet_target`, `pet_command`, `pet_skill`, `switch_pet` | The four-call sequence in `battle_action` |
| `battle_escape_dev` | `battle_id` | `developer_escape` |
| `battle_close` | `battle_id` | Client finished presenting the result; clears the battle slot |

`set_capture_assist` becomes backend state owned by the capture runner; manual battles never set it.

### Profile

One command per existing mutation, same arguments, pets addressed by `pet_id` wherever the current API allows it:

`buy_item`, `sell_item`, `use_item`, `equip_item`, `buy_travel_pass`, `heal`, `heal_carried_pets`, `store_pet`, `retrieve_pet`, `select_pet`, `mount_pet`, `rename_pet`, `set_pet_favorite`, `allocate_stat`, `distribute_stats`, `learn_pet_skill`, `set_character`, `accept_quest`, `claim_quest`, `grant_starter_pets`, `grant_pet_care_items`, `claim_default_companions`.

GM tools become one `gm` command with an `op` field (`clear_modified`, `raise_level`, `set_base_stat`, `grant_points`, `heal`). Rejected when not enabled for the session.

### Automation

| Command | Fields |
| --- | --- |
| `auto_start` | `kind`, `settings` |
| `auto_update` | `settings` (only fields safe to change mid-run, such as speed) |
| `auto_stop` | none |

`kind` values map to the existing loops:

| Kind | Current owner | Settings |
| --- | --- | --- |
| `train` | `training_helper` preset `attack` | Existing `settings` dictionary: `speed`, `xp`, `hp`, `level`, `limit`, `compact` |
| `capture_battle` | `training_helper.start_capture_battle` | `target`, `finish_battle`, capture settings |
| `pet_train` | `training_helper.start_pet_training` | `pet_id`, `target_level` |
| `hunt` | `pet_hunt_menu.start_hunt` | Existing `filter` dictionary, `auto_capture` |
| `find_pet` | `pet_workflow.start_cycle` | `species`, stat filter snapshot |

`find_pet` composes `hunt`, `capture_battle` and `pet_train` inside the backend, as `pet_workflow` does today. Only one runner is active at a time.

### Save

No `save`/`load` commands. The backend owns the save path, autosaves after settlements and on shutdown, and the client never reads the file. Tests start the backend with a temporary save path.

## Events

| Event | Payload | Replaces |
| --- | --- | --- |
| `snapshot` | `rev`, `profile`, `battle` or null, `automation`, `position`, `limits` (`pet_capacity`, `max_level`), `derived` (`effective_stats`, `has_travel_pass`, `can_fight_boss`, `gm_pending`) | All read-only queries and constants |
| `profile` | `rev`, `profile` without `pet_storage`, `derived` | Whole profile each time in v1 |
| `pet_storage` | `rev`, `pet_storage` | Sent only when storage changes; it is ~94% of a real save (48 of 49 KB with 86 stored pets) |
| `battle_started` | `battle_id`, `state` | `start_battle` return |
| `battle_turn` | `battle_id`, `turn`, `state`, `events` | `submit_action` return |
| `battle_ended` | `battle_id`, `outcome`, `rewards`, `summary` (`result_summary` rows, level-up lines) | Client-side diffing in `battle_action` |
| `encounter_skipped` | `reason` (`art`, `data`) | `last_encounter_error` |
| `auto_status` | `kind`, `running`, counters (`battles`, `skipped`, `earned_xp`, `earned_pet_xp`, `turns`), `stop_reason`, runner detail | `training_helper` fields read by UI |
| `hunt_progress` | `rolls`, `inspected`, `best`, `rate`, `elapsed`, `last_hit` | `pet_hunt_menu.summary()` inputs |
| `offline_summary` | battles, experience, captures since the last client disconnected | New, sent after `snapshot` on reconnect |

## Pacing

The backend advances automation on its own tick. Presentation never gates rules, but an attached client may slow the pace.

| Mode | When | Backend pace |
| --- | --- | --- |
| `paced` | Client attached, full battle view | After each `battle_turn`, wait for `presented {battle_id, turn}` or 5 s, whichever is first |
| `compact` | Client attached, compact battles | `0.25 / speed` seconds per step, as today |
| `detached` | No client | Fixed step budget per tick; hunt keeps its `rate` cap and backlog limit |

The 5 s ceiling means a frozen or backgrounded Safari tab cannot stall training.

## Content availability

Today a troop is skipped when the local client cannot render it. With on-demand downloads, a web client may simply not have fetched the art yet, so the backend must not ask the client.

- The asset build writes `renderable_sprites.json` from the same check `can_render_troop` performs.
- The backend loads it and applies today's skip rules (`encounter_skipped: art`, streak limit of 100). Behavior stays identical on desktop.
- Clients download missing art when `battle_started` arrives and show a loading state; that never changes the outcome.

## Movement

Movement stays client-driven in v1. The client sends `report_position` after each step and `field_step` on field cells. The backend trusts reported positions (single player, own MacBook). Automation runners stop when a reported position differs from their origin, matching today's "位置发生变化" rule. `MoveIntent` validation from [server rules](server.md) remains a later slice. `travel_router` stays a client navigator.

## Migration order

Each step keeps the desktop game playable and `scripts/test.sh` green.

1. `Backend`, `LocalLink`, `ClientState`, `hello`/`snapshot`/`profile`. Move read-only call sites (`snapshot`, `PET_CAPACITY`, `has_travel_pass`, `can_fight_boss`, `_pending`) to `ClientState`.
2. Profile and GM commands; delete `last_error` reads.
3. Battle: `battle_command`, events, backend-computed summary, encounter RNG and rolls, backend-owned seed, content manifest.
4. Automation runners: `train`, `capture_battle`, `pet_train`, then `hunt`, then `find_pet`. UI scripts keep panels and settings, lose loops.
5. Backend-owned saves and shutdown flush; tests switch to temporary save paths.
6. Later: headless entry scene and `WebSocketLink`, reconnect and `offline_summary`.

Steps 1–5 are estimated at 3–5 SP. Many of the ~80 suites in `scripts/test.sh` reach into `world.session` or `world.battle_session`; they migrate alongside their feature, and pure-rule suites should need no change.

## Decisions (2026-09-27)

1. Movement stays client-reported in v1; `MoveIntent` validation is a later slice.
2. `paced` mode waits for `presented` with a 5 s ceiling.
3. A newer connection takes control; the older one receives `superseded`.
4. Whole-state events, no diffs: `profile` excludes storage and `pet_storage` is sent only on change. Add diffs only if parse or UI rebuild cost on Vision Pro is measured as a problem.
