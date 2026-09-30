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
| Session | `hello` (protocol check, returns snapshot; a multi-profile server may ask for a login first, see below), `snapshot`, `ping` (heartbeat), `set_options` (`clone_squad`, `experience_multiplier`), `checkpoint` (`map_id`, `x`, `y`; saves) |
| Profile | `buy_item`, `sell_item`, `use_item`, `equip_item`, `buy_travel_pass`, `heal`, `store_pet`, `retrieve_pet`, `retrieve_pet_by_id`, `select_pet`, `mount_pet`, `rename_pet`, `set_pet_favorite`, `allocate_stat`, `distribute_stats`, `learn_pet_skill`, `set_character`, `set_automation_settings` (see below), `accept_quest`, `claim_quest`, `grant_starter_pets`, `claim_default_companions`, `gm_raise_level`, `gm_set_base_stat`, `gm_grant_points`, `gm_heal`, `gm_clear_modified`, and the radio library commands (see below). Pets: `release_pets` (`ids`; optional `source` `保留规则` with `template_id` when the selection came from 同种比较's 按保留规则选中, so the backend re-evaluates the rule and logs its reasons; otherwise `手动`), `prune_hunt_pets`, and `pet_log` (`kind` `caught` for 抓宠记录, `released` for 放生记录 or `stops` for 停止记录 (why the hunt or the find-pet cycle stopped, paused, skipped a hit or finished: {time, scope hunt|flow, outcome 停止|暂停|已跳过|已重试|完成|找到, reason, phase, run, rolls, collected, stored, skipped, released, map_id, map_name, cell, pet_id, name}; paged the same way, no species filter), `page` from 0, `page_size` 1 to 100, default 20, `template_id` or -1 for all, `run` "" for all, `latest` for the running or most recent find-pet run, or a run id, caught only; replies `log`: `entries` newest first, `total`, `page`, `pages`, `species` [{template_id, name, count}], `runs` [{run, count, time}] newest first, `latest_run`, `kind`; entries are cross-linked: a caught pet later released carries `released` {time, reason, source}, a released pet whose capture is logged carries `caught` {time, map_name, cell, source, run}). `release_log` is `pet_log` with `kind` `released`. Fields mirror the `GameSession` arguments (`PROFILE_COMMANDS` in `backend.gd`). |
| World | `report_position` (`map_id`, `cell`, `map_changed`, `client`; reply `paused` names a workflow pause), `field_step` (`encounter`: open the wild battle on a hit), `wild_encounter`, `begin_battle` (`boss`, `enemy_count`) |
| Battle | `battle_command` (`action`, `target`, `pet_target`, `switch_pet`, optional `pet_skill`), `battle_pet_command`, `battle_pet_skill`, `battle_escape_dev`, `battle_close`. Remote clients add `battle_id` and `turn`; a command for a turn already resolved is rejected as stale. |
| Fixtures | `start_battle_config`, `start_wild_battle_config`, `open_battle` (accepts only the pending config this backend issued) |
| Automation | `auto_start` (`kind`: `battle`, `capture_battle`, `pet_train`, `hunt`, `find_pet`; `map_id`, `cell`, the device's playback `speed`; the run uses the profile's settings, and an optional `settings` / `filter` / `stat_filters` from older clients overrides them for that run only), `auto_update` (run-only `settings`, `stat_filters`), `auto_stop`, `presented` (`battle_id`, `turn`), `auto` (named: `stop_battle`, `stop_hunt`, `stop_flow`, `acquire_clone`, `release_clone`, and the in-process ticks `tick_battle`, `hunt_process`, `flow_step`) |

Pets during a battle: until it settles, the battle's participants (`GameSession.battle_pets()`: the start roster's active pet and mount, the pet fighting now, any pet with kill credit, and in a capture-assist battle the capture helpers) cannot be released (skipped as `战斗中`), stored, or tidied by a keep rule; `select_pet` and `mount_pet` are refused for every pet. Other pets can be released, stored, withdrawn (while room for the battle's possible captures remains) and favourited. Clone squads are copies and never count. The settlement matches the result's roster slots to the party by pet id, and `battle_command` refuses to switch in a pet that left the party.

## Login on a multi-profile server

A server started with `--accounts=<file>` hosts several characters (`server/profile_hub.gd`, [LAN profiles](../development/lan-profiles.md)). A connection must log into one before any game command; afterwards every command goes to that character's `Backend` and only that character's events reach it. A lone server (no `--accounts`) and the desktop game never ask: `hello` returns the snapshot as before.

| Command | Fields | Reply |
| --- | --- | --- |
| `hello` | `protocol`, optional `login` {`name`, `token`} | logged in: `snapshot`, `account` {`name`, `admin`}, `token`; otherwise `ok` with `login_required`, `profiles` [{`name`, `admin`, `online`}], `allow_create` and, for a token that no longer works, `reason` |
| `login` | `name` (any case), `pin` | as a logged-in `hello`, with a new device `token`; or rejected with `reason` (and `locked` seconds after 5 wrong PINs in a row, for 300 s) |
| `create_profile` | `name` (1 to 16 characters, unique), `pin` (4 to 8 digits) | as `login`, plus `created`; refused when the accounts file sets `allow_create` false. The first character (or any while there is no admin) is the admin |
| `logout` | | forgets this device's token; the connection returns to the picker (`profiles`, `allow_create`) |
| `profiles` | | `profiles`, `allow_create` |

Before a login only these and `ping` are accepted; anything else is rejected with `login_required`. `WsLink` sends the remembered `login` with every `hello`, so reconnects skip the picker; it emits `login_needed` with the picker data otherwise, and `login()` sends `login` or `create_profile` (the game's `scripts/login_screen.gd`). The game keeps the name and token per server address in `viewer.cfg` (`logins`).

Every snapshot and `profile` event carries `options.admin` (always true without accounts) and, on a multi-profile server, `options.account`. A backend with `admin` false refuses `Backend.ADMIN_COMMANDS` (`battle_escape_dev`, `start_battle_config`, `start_wild_battle_config`, `open_battle`, `begin_battle`, `set_fast_hunt_threads`) and every `gm_*` with 「只有管理员角色可以使用 GM 和开发者功能。」.

## Presence and chat on a multi-profile server

LAN phase 2 (`server/presence.gd`, run by the hub; [LAN profiles](../development/lan-profiles.md)). Only a hub sends these; a lone server and the desktop game never do, and a lone backend rejects `say` as an unknown command.

| Message | Fields | Notes |
| --- | --- | --- |
| `presence` event | `map_id`, `full`, `players` [entry], optional `left` [ids] | To each logged-in connection, about the *other* profiles on its own profile's map. `full`: the complete list (first tick after a login or reconnect, and whenever the viewer's map changes; an empty list clears). Otherwise `players` holds new players in full and, for known ones, `id` plus only the changed keys. At most one per connection every 150 ms (`Presence.TICK_MSEC`), and none when nothing changed. |
| entry | `id` (profile id), `name` (account), `lv`, `c` (character id), `face`, `ride` (ridden pet's sprite, -1 none), `rn` (its name), `cell` [x, y], `f` (facing 0..7, from the last step), `b` (战斗中), `pt` (组队: the leader's id, "" none) | A profile is listed while one of its devices is connected and its map is known (from `report_position`). `b` is a battle open, or compact 自动练级 running, held 2 s after it ends. Walking is not sent: the client animates while it moves an actor towards `cell`. |
| `say` command | `text`, optional `channel` (`队伍`) | 一般频道. Trimmed, line breaks become spaces; 1 to 60 characters; at most 3 lines per 5 s per character (both channels together); needs a known map. With `channel` `队伍` (LAN phase 3) it goes to the speaker's party on any map, and is refused outside a party. Rejected with a Chinese `reason` otherwise. |
| `turn` command | `facing` (0 to 7) | 右键转向: the character turns in place; the next presence tick carries the new `f` to the others. The client sends it only to a hub. |
| `chat` event | `channel` (`一般`, `队伍` or `系统`), `map_id`, `id`, `name`, `text`, `mine` | 一般: to every device of every profile on the speaker's map, the speaker's own devices with `mine` true. 队伍: to every device of the party. 系统: a 组队 notice for this device's character (`id` and `name` empty), such as 「加入团队！」 or 「团队已解散！」. |

The same-profile `position` mirror (another device of *your* character walking) is unchanged and separate from `presence`.

### 组队 (LAN phase 3)

`server/party.gd`, run by the hub; behaviour in [LAN profiles](../development/lan-profiles.md#phase-3-组队-and-following-the-leader). Like `say`, only a hub accepts these; a lone backend rejects them as unknown commands.

| Message | Fields | Notes |
| --- | --- | --- |
| `party_switch` command | `on` | This character's 组队 switch: whether others may join it. Reply `accept`. Kept while the server runs. |
| `party_join` command | `facing` (0..7, the client's facing), optional `target` (a leader's profile id) | Joins the player on the cell in front (`Party.front`), or that player's leader if it is a member, when that leader is within one cell, not fighting, has its switch on, runs no automation and leads fewer than 5. The joiner must be on a map, out of a party, not fighting and running no automation. Reply `leader`, `members`, `created`; otherwise a Chinese `reason`. |
| `party_leave` command | | Leaves; a leader leaving disbands the party. |
| `party_kick` command | `id` | Leader only: removes that member. |
| `party_disband` command | | Leader only. |
| `party` event | `me`, `accept`, `leader` ("" out of a party), `members` [{`id`, `name`, `lv`}] (leader first), `battle` | To each logged-in device when its view changes (checked with the presence tick, and at once after a party command). `battle`: this device's character is a member and its leader has a battle open (the client shows 「队长战斗中」). |
| `presence` entry `pt` | leader's profile id, "" out of a party | The leader's own entry names itself. |
| `position` event, `client` `party` | `map_id`, `cell` | The server moved this member after its leader (a step in the line, or the leader's destination on a warp or map change). Every device of the member follows it like another device's walk. A member's own `report_position` is answered with `party` true and, when it differs, this event with the server's position. |

While a character is a member, the hub answers `field_step` with no encounter (`party` true) and refuses `wild_encounter`, `begin_battle` and `open_battle`. Anyone in a party gets `auto_start` refused. A character whose last device disconnects, logs out or logs into another character leaves its party (a leader's party disbands).

## Automation settings

Automation settings belong to the character: `profile.automation_settings` holds only the player's overrides, and effective values are the defaults in `client/data/automation_defaults.json` deep-merged with them (`client/scripts/automation_settings.gd`, shared by backend and clients). Sections: `training` (`xp`, `compact`, `hp`, `level`, `level_explicit`, `limit`, `preset`), `capture` (`hp`, `pet`, `pet_id`, `pet_max_level`), `hunt` (`template`, `level_one`, `auto_capture`, `train_after_capture`, `total`, `offsets`, `rate`, `limit`, `fast`: 本机极速模式, see [fast hunt](fast-hunt.md)) and `stat_filters` keyed by template id (`mode`, `stop_after`, `keep_rule` (保留规则, `client/scripts/keep_rule.gd`: `tiers` 0 to 20, default 2; `per_tier` 0 to 1000, default 3; `order`, 1 to 5 distinct keys of `sum`, `attack`, `defence`, `speed`, `max_hp`, default `["attack","speed","max_hp"]`, ties falling back to the remaining keys in `sum, attack, defence, speed, max_hp` order and then the lower pet id; `champions` 0 to 1000, default 2; `champion_stats`, any of `attack`, `defence`, `speed`, `max_hp`, default all four; `auto`, default false, tidies the whole species after each pet the find-pet cycle stores; it replaced `keep_qualified`/`rank`, and a stored `rank` becomes `order` without `sum`), `conditions.<sum|attack|defence|speed>.{enabled,value,strict,keep}`); the defaults file also carries per-species filter defaults under `species`.

`set_automation_settings` (`settings`: a partial object of that shape) validates every key, type and range first and rejects the whole update with a reason (`unknown setting training.speed`, `invalid hunt.offsets`); otherwise it deep-merges, drops overrides equal to their default, saves and publishes `profile` to every client. `null` resets a value, group or section to its default. A running capture follows capture changes at once; other settings apply from the next start, and a find-pet cycle keeps the stat conditions it started with. Older saves without the section load with defaults; invalid stored parts are dropped. Battle playback speed and minimized windows are per device (`user://viewer.cfg`) and never stored here; the backend paces an uncompacted run with the `speed` its starting device sent. The 本机极速模式 thread count is the server computer's own setting, neither the character's nor a device's: `set_fast_hunt_threads` (`threads`, 0 = automatic up to the core count) stores it in the backend's `user://server-settings.cfg` and the automation status publishes `hunt.threads`, `hunt.threads_used` and `hunt.cores` (see [fast hunt](fast-hunt.md)).

The radio library is the character's too: `profile.music` is `{favorites: [track ids], playlists: [{name, tracks: [track ids]}]}` (`client/scripts/music_library.gd`; track ids look like `sabgm_t0`, names are at most 20 characters, 50 playlists of 200 tracks). Changes are small operations so two devices editing at once do not overwrite each other: `set_music_favorite` (`track`, `favorite`), `create_music_playlist` (`name`), `rename_music_playlist` (`name`, `new_name`), `delete_music_playlist` (`name`), `add_music_to_playlist` (`name`, `track`), `remove_music_from_playlist` and `move_music_in_playlist` (`name`, `position`, `track`, and `step` of -1 or 1 for a move; refused when the entry at `position` is no longer `track`). They are allowed during battles. Whether a device plays the radio, its station, shuffle and last track are per device (`user://viewer.cfg`).

Clients show effective settings from `ClientState.profile` and send changes: choices at once, numbers once the player pauses (`game.mark_settings_dirty` / `flush_automation_settings`), everything on Apply or Start. When the profile changes, open windows update only values that changed, skipping a field being typed in or one with an unsent change of this device.

## Events

| Event | Payload |
| --- | --- |
| `snapshot` | `rev`, `profile` (with storage), `derived` (`has_travel_pass`, `can_fight_boss`, `effective_stats`, `gm_pending`, `battle_pets` (pet_id -> 出战中/骑乘中/削血宠 for the open battle's participants, see below), `pet_capacity`, `max_level`), `options`, `battle`, `battle_open`, `automation` |
| `profile` | `rev`, `profile` without `pet_storage`, `derived`, `options` |
| `pet_storage` | `rev`, `pet_storage`; only when storage changed (it is ~94% of a real save) |
| `battle_started` / `battle_turn` | `state`; a turn's state carries `turn_frames` to animate and, once settled, `settled`, `result_summary` and reward lines |
| `battle_state` | `state` after a non-turn change (pet command, capture assist); never animated |
| `battle_closed` | `battle_id`, `outcome`; a defeat also moves the saved location to the village |
| `auto_status` | Runner counters, settings, origin, `hunt` and `flow` sub-status |
| `auto_event` | `detail.kind`: `battle_stopped` (`takeover` hands a live battle to manual control), `battle_refused`, `hunt_stopped`, `hunt_refused`, `hunt_hit`, `flow_hunt`, `flow_paused`, `flow_stored`, `flow_compare` |
| `position` | `map_id`, `cell`, `client`: the character moved; other clients mirror it |
| `pet_log_changed` | `revision`: entries were appended to 抓宠记录, 放生记录 or 停止记录; an open 宠物记录 window fetches its page again (at most twice a second) |

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

放生记录 (release log, `client/server/release_log.gd`) is kept out of the save so loading never reads it: one JSON line per released pet in `<save>.release-log.jsonl` next to the save (`single-player.release-log.jsonl`), appended after each command or automation tick that released pets (`GameSession.release_events`, drained by `Backend._record_releases`). It holds at most `CAP` 5,000 entries: past `CAP` + `SLACK` (500) lines it is rewritten once with the newest 5,000, so a long hunt does not rewrite it on every release. The file is first read to answer `release_log` or to count lines before the first append. Without a save (most tests) it stays in memory under the same cap; `Backend.release_log_path` overrides the file. Entry: `time` (UTC seconds), `pet_id`, `name`, `template_id`, `species`, `level`, `attack`, `defence`, `speed`, `max_hp`, `sum`, `lv120` (the judged Lv120 stats for younger pets), `offsets`, `full`, `where` (随身/仓库), `source` (手动, 保留规则, 自动整理, 未达标整理), `reason`, `beaten_by` [{`pet_id`, `name`, `attack`, `defence`, `speed`, `max_hp`, `sum`}]. Keep-rule reasons and beaters come from `KeepRule.evaluate`'s `why` (see its `_explain`).

抓宠记录 (capture log) is the same kind of file, `<save>.capture-log.jsonl`, with the same cap. `GameSession.capture_events` records each pet a battle capture settles or `gm_grant_pet` adds; the backend stamps the source when it drains them: `找宠流程` while the find-pet cycle is active (with `run`, `Automation.flow_run_id`, set when a new cycle starts and kept across its restarts), `自动抓宠` while the automation fights its capture preset, `手动捕获` otherwise, `GM发放` for grants. Entry: `time`, `pet_id`, `name`, `template_id`, `species`, `level` (at capture), `attack`, `defence`, `speed`, `max_hp`, `sum`, `lv120` (exact, `Progression.project_pet`, for pets under Lv120), `offsets`, `full`, `map_id`, `map_name` (world catalog), `cell`, `source`, `run`.

A `WsLink` pings every 3 s and drops a connection that has been silent for 10 s, so a killed server or dropped network is noticed even without a close frame. While offline the game is covered by a notice with the retry countdown and ignores input. It reconnects with backoff (1 s doubling to 10 s). On reconnect the `hello` reply's snapshot replaces client state, the game reopens or closes the battle view to match, and it shows a summary of battles, levels and new pets gained while offline. Any number of clients can be connected and drive the session. The server handles commands one at a time and sends every event to every client, so the first of two conflicting commands wins; the loser is rejected by the rules, and replies marked `stale` (another device already opened, closed or advanced the battle) are not shown as errors. Paced battles advance on the first `presented`.

Walking is mirrored: each client tags `report_position` with its id, the backend broadcasts `position` when the character moves, and other clients walk one cell or jump to the reported spot, loading its map when it differs. Mirrored steps skip arrival rules (encounters, map links) and are not reported back, because the walking client already ran them. Local input cancels mirroring.

## Test seams

Tests may still reach authority internals through `world.session._profile`, `_pending`, `world.battle_session._state` and similar. These work only with a `LocalLink`; once used, every client read resyncs from the backend. `game.sync_state()` resyncs after changing `game.backend` directly. `scripts/test-all.sh` runs every suite in parallel and reports each; `backend_automation_test` and `remote_link_test` cover detached automation and the WebSocket path; `automation_settings_test` and `remote_settings_test` cover profile settings; `radio_test` covers the radio library across two devices. `profile_hub_test` and `remote_login_test` cover multi-profile servers (routing, logins, admin gating, per-profile saves and resume, the login screen); `lan_presence_test` covers the presence feed, chat and the client's presence model; `lan_party_test` covers 组队 (rules, following, leader-only encounters, automation gating, 队伍频道, disconnects and a game client as a member).

## Decisions (2026-09-27)

1. Movement stays client-reported in v1; `MoveIntent` validation is a later slice.
2. Paced automation waits for `presented` with a 5 s ceiling.
3. Several connections share the session; the first conflicting command wins (revised 2026-09-28 from newest-takes-control).
4. Whole-state events, no diffs: `profile` excludes storage and `pet_storage` is sent only on change. Add diffs only if parse or UI rebuild cost on Vision Pro is measured as a problem.

Differences from the first proposal: the local link replies synchronously (the `done` callback keeps call sites asynchronous-safe); GM tools are flat `gm_*` commands; troop art is checked directly instead of from a generated sprite list; the offline summary is computed by the client from the reconnect snapshot.
