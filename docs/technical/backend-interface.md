# Backend interface

Status: implemented on `feat/backend-split` (2026-09-27). The game is a backend-driven simulation; every client (the desktop window, a web build on Vision Pro Safari) only sends commands and settings and presents state. This refines [architecture](architecture-overview.md), [networking](networking.md) and [local sessions](local-server.md).

## Shape

```text
client scripts ──► link.request(command, done) ──► Backend.handle(command)
      ▲                                                   │
      └──── ClientState ◄──── link.message(event) ◄───────┘
```

| Piece | File | Role |
| --- | --- | --- |
| `Backend` | `client/server/backend.gd` | Owns `GameSession`, the current battle, encounter catalog and RNG, automation and the save path. No scene nodes, textures or audio. |
| `Automation` | `client/server/automation.gd` | Auto battles (attack, capture, pet training), hunt scanning and the find-pet workflow. |
| `TroopArt` | `client/server/troop_art.gd` | Shared art check; the backend skips troops from its own asset set, never from what one client has downloaded. |
| `LocalLink` | `client/network/local_link.gd` | In-process delivery. Deep-copies both ways; replies complete synchronously. |
| `WsLink` / `WsServer` | `client/network/ws_link.gd`, `client/server/ws_server.gd` | JSON over WebSocket (`codec.gd` restores integers). |
| `ClientState` | `client/network/client_state.gd` | Latest snapshot, battle and automation status. UI reads only this. |
| `SessionClient` / `BattleClient` | `client/network/` | `world.session` and `world.battle_session`: GameSession-shaped reads from `ClientState`, commands for every change. |

The desktop game builds a `Backend` and a `LocalLink`. `scripts/serve.sh` runs `server_main.gd` headless with a `WsServer`; a client started with `--server=ws://host:8781` (or a web build, which defaults to the page host) uses `WsLink` and holds no authority.

## Envelope

Commands are `{"type": ..., "seq": n, ...fields}`. Each gets exactly one reply `{"type": "ack"|"rejected", "seq": n, "ok": bool, "reason": ...}`; over WebSocket replies also carry `"reply": true`. Events carry `"v"` (protocol, currently 1) and `"rev"` where they replace profile state. Values are JSON-safe; cells are `[x, y]`.

`request(command, done)` returns the reply on a `LocalLink` and also passes it to `done`. On a `WsLink` it returns `{"pending": true}` and calls `done` later, and a non-ok reply is also emitted as a `rejected` message the game shows. `SessionClient` treats pending as sent. Commands are never queued while offline, so purchases and battle actions cannot replay after a reconnect.

Events raised while the backend handles a command or ticks are queued and delivered when it finishes, before the reply. Client reactions (for example a defeat returning to the village, which reports a new position) therefore never re-enter a half-applied change.

## Commands

| Group | Types |
| --- | --- |
| Session | `hello` (protocol check, returns snapshot), `snapshot`, `ping` (heartbeat), `set_options` (`clone_squad`, `experience_multiplier`), `checkpoint` (`map_id`, `x`, `y`; saves) |
| Profile | `buy_item`, `sell_item`, `use_item`, `equip_item`, `buy_travel_pass`, `heal`, `store_pet`, `retrieve_pet`, `retrieve_pet_by_id`, `select_pet`, `mount_pet`, `rename_pet`, `set_pet_favorite`, `allocate_stat`, `distribute_stats`, `learn_pet_skill`, `set_character`, `accept_quest`, `claim_quest`, `grant_starter_pets`, `claim_default_companions`, `gm_raise_level`, `gm_set_base_stat`, `gm_grant_points`, `gm_heal`, `gm_clear_modified`. Fields mirror the `GameSession` arguments (`PROFILE_COMMANDS` in `backend.gd`). |
| World | `report_position` (`map_id`, `cell`, `map_changed`; reply `paused` names a workflow pause), `field_step` (`encounter`: open the wild battle on a hit), `wild_encounter`, `begin_battle` (`boss`, `enemy_count`) |
| Battle | `battle_command` (`action`, `target`, `pet_target`, `switch_pet`, optional `pet_skill`), `battle_pet_command`, `battle_pet_skill`, `battle_escape_dev`, `battle_close` |
| Fixtures | `start_battle_config`, `start_wild_battle_config`, `open_battle` (accepts only the pending config this backend issued) |
| Automation | `auto_start` (`kind`: `battle`, `capture_battle`, `pet_train`, `hunt`, `find_pet`; plus `settings`, `map_id`, `cell`), `auto_update` (`settings`, `stat_filters`), `auto_stop`, `presented` (`battle_id`, `turn`), `auto` (named: `stop_battle`, `stop_hunt`, `stop_flow`, `acquire_clone`, `release_clone`, and the in-process ticks `tick_battle`, `hunt_process`, `flow_step`) |

## Events

| Event | Payload |
| --- | --- |
| `snapshot` | `rev`, `profile` (with storage), `derived` (`has_travel_pass`, `can_fight_boss`, `effective_stats`, `gm_pending`, `pet_capacity`, `max_level`), `options`, `battle`, `battle_open`, `automation` |
| `profile` | `rev`, `profile` without `pet_storage`, `derived`, `options` |
| `pet_storage` | `rev`, `pet_storage`; only when storage changed (it is ~94% of a real save) |
| `battle_started` / `battle_turn` | `state`; a turn's state carries `turn_frames` to animate and, once settled, `settled`, `result_summary` and reward lines |
| `battle_state` | `state` after a non-turn change (pet command, capture assist); never animated |
| `battle_closed` | `battle_id`, `outcome`; a defeat also moves the saved location to the village |
| `auto_status` | Runner counters, settings, origin, `hunt` and `flow` sub-status |
| `auto_event` | `detail.kind`: `battle_stopped` (`takeover` hands a live battle to manual control), `battle_refused`, `hunt_stopped`, `hunt_refused`, `hunt_hit`, `flow_hunt`, `flow_paused`, `flow_stored`, `flow_compare` |
| `superseded` | Sent to the older connection before a newer one takes control |

## Automation and pacing

A standalone backend ticks its runners itself, keeps settling and saving with no client, and marks itself detached so nothing waits on presentation. In-process, the backend does not tick: each control's frame loop drives its runner (`tick_battle`, `hunt_process`, `flow_step`) so pausing a control pauses its runner, as before the split.

| Mode | Pace |
| --- | --- |
| Full battle view, client attached | Waits for `presented` of the current turn, at most 5 s (`PRESENT_TIMEOUT_MSEC`) |
| Compact battles | `0.25 / speed` seconds per step |
| No client | No presentation wait; hunt keeps its `rate` cap and backlog limit |

Clients also compare their own position with the runner's origin and stop it when they move, which covers movement the backend has not been told about yet.

## Movement, saves and reconnects

Movement stays client-driven and trusted (single player, own MacBook); `MoveIntent` validation remains a later slice. The backend owns the save: autosave after accepted mutations and settlements, and on `checkpoint`. The desktop game points it at `user://single-player.json`; `serve.sh` uses the same file by default, so do not run both against it at once.

A `WsLink` pings every 3 s and drops a connection that has been silent for 10 s, so a killed server or dropped network is noticed even without a close frame. While offline the game is covered by a notice with the retry countdown and ignores input. It reconnects with backoff (1 s doubling to 10 s). On reconnect the `hello` reply's snapshot replaces client state, the game reopens or closes the battle view to match, and it shows a summary of battles, levels and new pets gained while offline. A newer connection takes control; the older client is told, stops reconnecting and offers "在此设备继续" to take control back.

## Test seams

Tests may still reach authority internals through `world.session._profile`, `_pending`, `world.battle_session._state` and similar. These work only with a `LocalLink`; once used, every client read resyncs from the backend. `game.sync_state()` resyncs after changing `game.backend` directly. `scripts/test-all.sh` runs every suite in parallel and reports each; `backend_automation_test` and `remote_link_test` cover detached automation and the WebSocket path.

## Decisions (2026-09-27)

1. Movement stays client-reported in v1; `MoveIntent` validation is a later slice.
2. Paced automation waits for `presented` with a 5 s ceiling.
3. A newer connection takes control; the older one receives `superseded`.
4. Whole-state events, no diffs: `profile` excludes storage and `pet_storage` is sent only on change. Add diffs only if parse or UI rebuild cost on Vision Pro is measured as a problem.

Differences from the first proposal: the local link replies synchronously (the `done` callback keeps call sites asynchronous-safe); GM tools are flat `gm_*` commands; troop art is checked directly instead of from a generated sprite list; the offline summary is computed by the client from the reconnect snapshot.
