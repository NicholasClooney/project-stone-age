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
| Profile | `buy_item`, `sell_item`, `use_item`, `equip_item` (the club, the mirror, and the 精灵 equipment `haru_armor`, `freya_robe`, `teo_robe`, `koyala_charm`; refused with `reason` 能力不足无法装备。 below the item's level and 无法同时装备两项同种类的物品。 for a second amulet), `use_spirit` (`slot` `body`/`amulet`, `target` 0 the player or k the k-th carried pet: a worn FIELD_ALL healing 精灵 outside battle; the reply's `note` says 耐久力回复N; refused with 气力不足。 and friends), `buy_travel_pass`, `heal` (also restores 气力), `store_pet`, `retrieve_pet`, `retrieve_pet_by_id`, `select_pet`, `mount_pet`, `rename_pet`, `set_pet_favorite`, `allocate_stat`, `distribute_stats`, `learn_pet_skill`, `set_character`, `set_free_spirits` (`on`: 精灵不耗气力, a non-original rule saved as `profile.free_spirits`, on when missing; the spirits then report `mp` 0 and battle configs carry `mirror_mp` 0), `set_automation_settings` (see below), `accept_quest`, `claim_quest`, `grant_starter_pets`, `claim_default_companions`, `gm_raise_level`, `gm_set_base_stat`, `gm_grant_points`, `gm_heal` (the player's 气力 too), `gm_grant_spirits` (one piece of each spirit equipment and full 气力), `gm_clear_modified`, and the radio library commands (see below). Pets: `release_pets` (`ids`; optional `source` `保留规则` with `template_id` when the selection came from 同种比较's 按保留规则选中, so the backend re-evaluates the rule and logs its reasons; otherwise `手动`), `prune_hunt_pets`, and `pet_log` (`kind` `caught` for 抓宠记录, `released` for 放生记录 or `stops` for 停止记录 (why the hunt or the find-pet cycle stopped, paused, skipped a hit or finished: {time, scope hunt|flow, outcome 停止|暂停|已跳过|已重试|完成|找到, reason, phase, run, rolls, collected, stored, skipped, released, map_id, map_name, cell, pet_id, name}; paged the same way, no species filter), `page` from 0, `page_size` 1 to 100, default 20, `template_id` or -1 for all, `run` "" for all, `latest` for the running or most recent find-pet run, or a run id, caught only; released only: `sort` `sum`/`attack`/`defence`/`speed`/`max_hp` orders by that stat (the Lv120 one when logged under Lv120) highest first, `ascending` true for lowest first, ties newest first, and `uncaught` true keeps only hits the 后台搜宠 queue let go; replies `log`: `entries` newest first, `total`, `page`, `pages`, `species` [{template_id, name, count}], `runs` [{run, count, time}] newest first, `latest_run`, `kind`; entries are cross-linked: a caught pet later released carries `released` {time, reason, source}, a released pet whose capture is logged carries `caught` {time, map_name, cell, source, run}). `release_log` is `pet_log` with `kind` `released`. `hunt_queue` replies `queue` (automation.gd `queue_view`): `active` (a find-pet cycle with 后台搜宠), `showcase`, `phase`, `limit` (per species), `size` (all species), `groups` [{template_id, name, count}] (one queue per species, template id order), `entries` [{rank (within its species' queue; 0 for the hit being caught or trained, which comes first with `current` and `phase`), roll, name, template_id, level, offsets, total_offset, full, survey, attack, defence, speed, max_hp, sum (predicted Lv.120)}]; the automation status's `flow.current_roll` and `flow.queue` tell an open 排队 tab when to fetch again. Fields mirror the `GameSession` arguments (`PROFILE_COMMANDS` in `backend.gd`). |
| World | `check_passage` (`from_map`, `to_map`; checks current server map and the profile permit for Seimu sea gates), `report_position` (`map_id`, `cell`, `map_changed`, `client`; reply `paused` names a workflow pause), `field_step` (`encounter`: open the wild battle on a hit), `wild_encounter`, `begin_battle` (`boss`, `enemy_count`) |
| Battle | `battle_command` (`action`, `target`, `pet_target`, `switch_pet`, optional `pet_skill`), `battle_pet_command`, `battle_pet_skill`, `battle_escape_dev`, `battle_close`. Remote clients add `battle_id` and `turn`; a command for a turn already resolved is rejected as stale. A 精灵 is `action` `spirit:<slot>` (`body` or `amulet`, a key of the state's `spirits`) with `target` a code of the caster's own screen: 0 itself, 1 its pet, 2+2i ally i, 3+2i ally i's pet, 20 its whole side (see [magic and MP](../reverse-engineering/magic-and-mp.md)); `mirror_self` / `mirror_pet` now spend 5 气力. |
| Fixtures | `start_battle_config`, `start_wild_battle_config`, `open_battle` (accepts only the pending config this backend issued) |
| Automation | `auto_start` (`kind`: `battle`, `capture_battle`, `pet_train`, `hunt`, `find_pet`; `map_id`, `cell`, the device's playback `speed`; the run uses the profile's settings, and an optional `settings` / `filter` / `stat_filters` from older clients overrides them for that run only), `auto_update` (run-only `settings`, `stat_filters`), `auto_stop`, `presented` (`battle_id`, `turn`), `auto` (named: `stop_battle`, `stop_hunt`, `stop_flow`, `acquire_clone`, `release_clone`, and the in-process ticks `tick_battle`, `hunt_process`, `flow_step`) |

气力 and 精灵 in the profile and the battle: `profile.player.mp` (0 to 100; `SAVE_VERSION` 4, older saves load with it full), `profile.equipment` {`body`, `amulet`: an item key or ""}; the battle state carries `player_mp`, `spirits` {slot: {`item`, `item_name`, `magic`, `name`, `comment`, `mp`, `kind` recovery|ressurect, `target` 0|1|8, `field`, `dead`, `power`}}, and each turn frame `player_mp` and, for a cast, `spirit` {`slot`, `name`, `kind`, `caster` / `target` refs {`kind` player|pet|ally|ally_pet|side, `index`}, `user_effect`, `effect`, `heals` [{`kind`, `index`, `amount`, `mount_amount`, `revived`}]}. The settlement takes `player_mp` and refuses more than the battle started with.

`mount_pet_as` is the pet window's confirmed appearance-and-mount transaction. Required fields: `pet_id` (stable carried UID), `character_id` (selected appearance), `expected_character` (appearance when the chooser opened), `map_id`, and `cell: [x,y]` (the chooser's field position). The backend rejects changed appearance/location, missing UID, invalid appearance or absent indexed original composite, an open/pending battle (including party battles), and active automation. It then applies all ordinary mount rules (deployment, current mount, health, loyalty, level and certificates), changes appearance and mounts together, saves, and publishes one profile update. Save failure restores the whole prior profile and publishes nothing. No new save fields or protocol revision are needed. Existing snapshot and LAN presence fields carry both changes; remote UI never accesses a backend. Cancelling or browsing previews sends no mutation. The chooser waits for the request callback (not the remote link's pending return value), disables repeat confirmation until acknowledgement, and keeps the selection with an explicit explanation on rejection. Asset downloads carry a cancellable intent generation; closing, replacing the pet, disconnecting or changing position invalidates old callbacks, and weak references protect destroyed views. This chooser is a project convenience; it uses only source-indexed rider/pet pairs, never cross-version sprite guesses.

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
| `party_share_exp` command | `on` | Leader only (LAN phase 4a): 「队伍共享经验」, on by default, for the party's next battle. Reply `share_exp`; every member hears a 系统 line. |
| `party_leave` command | | Leaves; a leader leaving disbands the party. |
| `party_kick` command | `id` | Leader only: removes that member. |
| `party_disband` command | | Leader only. |
| `party` event | `me`, `accept`, `leader` ("" out of a party), `members` [{`id`, `name`, `lv`}] (leader first), `battle`, `share_exp` | To each logged-in device when its view changes (checked with the presence tick, and at once after a party command). `battle`: this device's character is a member, is not fighting itself, and its leader has a battle open (the client shows 「队长战斗中」; in phase 4a that is a member who escaped from the party's battle). `share_exp`: the party's 「队伍共享经验」 (true outside a party). |
| `presence` entry `pt` | leader's profile id, "" out of a party | The leader's own entry names itself. |
| `position` event, `client` `party` | `map_id`, `cell` | The server moved this member after its leader (a step in the line, or the leader's destination on a warp or map change). Every device of the member follows it like another device's walk. A member's own `report_position` is answered with `party` true and, when it differs, this event with the server's position. |

While a character is a member, the hub answers `field_step` with no encounter (`party` true) and refuses `wild_encounter`, `begin_battle` and `open_battle`. In a party `auto_start` is refused except the leader's `battle` kind with the 普通攻击 preset (LAN phase 4c, below). A character whose last device disconnects, logs out or logs into another character leaves its party (a leader's party disbands); during a party battle only once that battle ends.

### Party battles (LAN phase 4a)

`server/party_battles.gd` and `server/party_battle_session.gd`; behaviour in [LAN profiles](../development/lan-profiles.md#phase-4a-party-battles). When a party leader's backend opens a battle, every member not already fighting joins it, and each participant's backend holds that player's view of it as its `battle`. The usual battle messages then work per player:

| Message | Fields | Notes |
| --- | --- | --- |
| `battle_started` / `battle_turn` / snapshot `battle` | the usual state, plus `party_slot` (0 the leader, 1..4 the members), `party` {`slot`, `share_exp`, `seconds` (left on the 45 s turn timer when sent), `sent` (this slot's command is in), `members` [{`slot`, `name`, `sent`, `down`, `out`, `auto`}]}, `party_fallen` | Seen from this player's side: `player_*`, `pet*`, `pets`, `potions`, `ride_pet`, `last_player_command` and `last_pet_command` are this player's; `allies` / `ally_pets` are the other players (the leader first on a member's screen) with `escaped` on one who left; turn frames and `events` are remapped the same way. `battle_id` and `turn` are shared. `active` goes false for this player when they escape or the battle ends; `party_fallen` marks a player who fell in a battle the others won (they get up with 1 HP). `can_capture` and `mirror_available` are false; `healing_available` is this player's own 恢复护符 (LAN phase 4c); `player_mp` and `spirits` are this player's, and a frame's `spirit` refs are remapped to this player's screen. |
| `battle_command` command | `action`, `target`, `pet_target`, `battle_id`, `turn`, `slot` | This player's command for the turn: `attack`, `defend`, `item`, `escape`, `spirit:<slot>` (its own 气力 and spirits; `target` as on its own screen, so a member heals the leader with 2 and revives a fallen teammate with 复活精灵). A `slot` other than this player's, or an old turn, is dropped as stale. `capture`, `switch` and `mirror_*` are rejected (`heal_pet` is accepted with the player's own 恢复护符 and a living, hurt pet, since phase 4c) with a Chinese `reason`, as is a player who fell or escaped. The reply carries the state; the turn resolves when every standing player with a device online has sent one (or the timer runs out) and then comes to every participant as `battle_turn`. |
| `battle_pet_command`, `battle_pet_skill` | as usual, plus `slot` | This player's pet's standing order. |
| `battle_state` event | `state` | A command came in and the turn still waits: `party` shows who has sent. |
| `battle_close` command | | As usual, once `active` is false for this player (escaped, or the battle over). A total defeat has already moved the server position to the village. |

Each player is settled on their own save (`GameSession.apply_battle_result` with that player's slice: their own pending battle id, `party_xp` {`player`, `pets` [per roster slot]} and `party_stay`) when they leave the battle or it ends. `battle_escape_dev` and a runner's abandon end the whole battle without rewards. The leader's 自动练级 and members' 自动战斗: phase 4c below.

### Automation in a party (LAN phase 4c)

Behaviour in [LAN profiles](../development/lan-profiles.md#phase-4c-自动练级-in-a-party). No new commands; what changes:

| Message | Notes |
| --- | --- |
| `auto_start` in a party | The leader's `kind` `battle` is accepted when the effective preset (the profile's `training.preset`, or a run-only `settings.preset`) is `attack` and no `capture_target` is given; every troop it meets opens a party battle. Refused with a Chinese `reason`: `hunt`, `find_pet` and `capture_battle` for everyone, `pet_train`, any kind for a member, another preset for the leader, and the leader of a party battle still running without it. |
| `set_automation_settings` `party` | `{auto, compact}` (bools; `auto` default false, `compact` default true): 组队自动战斗 and its 快速战斗, the character's own, used while it is a member. With `auto` the member's slot is automatic (`party.members[].auto` true in the battle state): the server commands it from the member's preset every turn and the turn never waits for it. A change sends every participant a `battle_state`. |
| `battle_close` | Optional `battle_id`: when it no longer names the open battle (the server already closed that one for the leader's next troop) the reply is `stale`, not an error. |
| `auto_event` `battle_stopped` | Also when the party changes under the leader's run: a member leaves or is kicked, the party disbands, the leader's last device disconnects, the whole party falls, or someone is at their own 停机线 and 恢复护符 and 回复药 cannot lift them (`reason` names who and why). Before that the run heals: between troops each player's 恢复护符 heals their carried pets and a player at the line casts a worn field 精灵 (治愈, 滋润; 用精灵补血, their own `training.spirit`) while the 气力 lasts, then drinks 回复药; in a battle the leader's run and 自动战斗 members cast a healing 精灵 first (themselves or a teammate at the line, 复活精灵 on a fallen one), then use `heal_pet` and `item`. |

A member whose previous party battle is finished but still open (its device shows the result, or 快速战斗 has not closed it yet) is closed by the server (`battle_closed`) when the leader opens the next battle, and enters it.

## Automation settings

Automation settings belong to the character: `profile.automation_settings` holds only the player's overrides, and effective values are the defaults in `client/data/automation_defaults.json` deep-merged with them (`client/scripts/automation_settings.gd`, shared by backend and clients). Sections: `training` (`xp`, `compact`, `spirit` (用精灵补血, default true: a healing 精灵 before a 回复药 or a stop at the 停机线), `side_heal` (全体补血, 0 to 100, default 50, 0 off: a worn 恩惠 on the whole side when anyone on it is below that percent), `hp`,
 `level`, `level_explicit`, `limit`, `preset`), `party` (`auto`, `compact`: LAN phase 4c 组队自动战斗 and 快速战斗), `capture` (`hp`, `pet`, `pet_id`, `pet_max_level`), `hunt` (`template`, `level_one`, `auto_capture`, `train_after_capture`, `total`, `offsets`, `rate`, `limit`, `fast`: 本机极速模式, see [fast hunt](fast-hunt.md); `stop_after`: 找到N只后停止, 0 to 100000, default 1, one count for the whole find-pet run: pets it keeps, qualifiers or with no enabled conditions every pet trained to Lv.120, 0 never stops, 1 stops at the first to compare) and shared `hunt.keep_rule` (保留规则, `client/scripts/keep_rule.gd`: `tiers` 0 to 20, default 2; `per_tier` 0 to 1000, default 3; `order`, 1 to 5 distinct keys of `sum`, `attack`, `defence`, `speed`, `max_hp`, default `["attack","speed","max_hp"]`, ties falling back to the remaining keys in `sum, attack, defence, speed, max_hp` order and then the lower pet id; `champions` 0 to 1000, default 2; `champion_stats`, any of `attack`, `defence`, `speed`, `max_hp`, default all four; `auto`, default false, tidies the whole species after each pet the find-pet cycle stores; all species use the same rule, evaluated separately within each species; it replaced `keep_qualified`/`rank`, and a stored `rank` becomes `order` without `sum`), and `stat_filters` keyed by template id (`mode`, `threshold_mode`, `conditions.<sum|attack|defence|speed>.{enabled,minus,value,keep}`; a per-species `stop_after` from older clients is accepted and ignored, and an older save's becomes `hunt.stop_after`); the defaults file also carries per-species filter defaults under `species`.

`set_automation_settings` (`settings`: a partial object of that shape) validates every key, type and range first and rejects the whole update with a reason (`unknown setting training.speed`, `invalid hunt.offsets`); otherwise it deep-merges, drops overrides equal to their default, saves and publishes `profile` to every client. `null` resets a value, group or section to its default. A running capture follows capture changes at once; other settings apply from the next start, and a find-pet cycle follows live edits to species thresholds and the shared keep rule; a pet already being caught/trained retains its captured threshold context while subsequent tidy uses the current shared keep rule. Older saves without the section load with defaults; invalid stored parts are dropped. Battle playback speed and minimized windows are per device (`user://viewer.cfg`) and never stored here; the backend paces an uncompacted run with the `speed` its starting device sent. The 本机极速模式 thread count is the server computer's own setting, neither the character's nor a device's: `set_fast_hunt_threads` (`threads`, 0 = automatic up to the core count) stores it in the backend's `user://server-settings.cfg` and the automation status publishes `hunt.threads`, `hunt.threads_used` and `hunt.cores` (see [fast hunt](fast-hunt.md)).

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

抓宠记录 (capture log) is the same kind of file, `<save>.capture-log.jsonl`, with the same cap. `GameSession.capture_events` records each pet a battle capture settles or `gm_grant_pet` adds; the backend freezes the entry synchronously through `GameSession.capture_entry_hook` before each new pet joins carried/storage inventory (before automatic training or keep-rule cleanup), and drains the already frozen entries afterward: `找宠流程` while the find-pet cycle is active (with `run`, `Automation.flow_run_id`, set when a new cycle starts and kept across its restarts), `自动抓宠` while the automation fights its capture preset, `手动捕获` otherwise, `GM发放` for grants. Entry: `time`, `pet_id`, `name`, `template_id`, `species`, `level` (at capture), `attack`, `defence`, `speed`, `max_hp`, `sum`, `lv120` (exact, `Progression.project_pet`, for pets under Lv120), `offsets`, `full`, `map_id`, `map_name` (world catalog), `cell`, `source`, `run`.


`capture_decision` is optional on historical records. It stores `at: before_inventory_join`, combinable `tags` (`stats`, `survey`, `unconditional`, `mixed_if_stats`; manual/GM/automatic presets use `manual`/`gm`/`automatic`), frozen saved `rule`, actual resolved capture-entry `thresholds`, and server-produced `threshold_text`. `stats` means the actual Lv120 projection satisfies that resolved gate; survey does not imply passing an unresolved gate. Manual/GM captures do not claim automatic filter acceptance. The gate is the filter used to enter this capture battle, while comparisons describe inventory immediately before the captured pet joins.

`metrics` stores `{key, value, rank, ties, original_max}` in `StatFilter.rank_order` / queue comparison order (default attack, speed, max_hp, sum, defence). Values use exact same-species Lv120 projection for carried/storage pets and waiting hits. Candidate/current duplicates and repeated owned IDs or waiting seed/roll/slot IDs are excluded. Competition rank is 1 plus the count strictly higher on that metric; `ties` counts other equal pets, explicitly shown as 并列. `original_max` is null without any same-species comparison pet, displayed as —. Inventory/rule changes, training, save reload, and remote RPC cannot recompute these historical fields.

Optional `queue` stores actual `admission_rank` after queue insertion/pruning, `departure_rank` at selection, `queued_at`, `dequeued_at`, and `wait_seconds` between those two instants. Rankings are within this species and use the actual lexicographic queue order (including earlier-roll tie breaking), independently of per-metric competition ranks. Older queue entries without measured timestamps omit unavailable fields. 抓到 rows show server tags and open their frozen comparison in a clickable detail dialog; old entries show —. The client only formats server data.

A `WsLink` pings every 3 s and drops a connection that has been silent for 10 s, so a killed server or dropped network is noticed even without a close frame. While offline the game is covered by a notice with the retry countdown and ignores input. It reconnects with backoff (1 s doubling to 10 s). On reconnect the `hello` reply's snapshot replaces client state, the game reopens or closes the battle view to match, and it shows a summary of battles, levels and new pets gained while offline. Any number of clients can be connected and drive the session. The server handles commands one at a time and sends every event to every client, so the first of two conflicting commands wins; the loser is rejected by the rules, and replies marked `stale` (another device already opened, closed or advanced the battle) are not shown as errors. Paced battles advance on the first `presented`.

Seimu sea portals between 40 and 31301/31401/31501 require the same profile `travel_pass` in both directions. The client requests `check_passage` before transitioning; the backend also rejects a direct `report_position` across those pairs without the permit. Original coordinates and destinations remain unchanged.

Walking is mirrored: each client tags `report_position` with its id, the backend broadcasts `position` when the character moves, and other clients walk one cell or jump to the reported spot, loading its map when it differs. Mirrored steps skip arrival rules (encounters, map links) and are not reported back, because the walking client already ran them. Local input cancels mirroring.

## Test seams

Tests may still reach authority internals through `world.session._profile`, `_pending`, `world.battle_session._state` and similar. These work only with a `LocalLink`; once used, every client read resyncs from the backend. `game.sync_state()` resyncs after changing `game.backend` directly. `scripts/test-all.sh` runs every suite in parallel and reports each; `backend_automation_test` and `remote_link_test` cover detached automation and the WebSocket path; `automation_settings_test` and `remote_settings_test` cover profile settings; `radio_test` covers the radio library across two devices. `profile_hub_test` and `remote_login_test` cover multi-profile servers (routing, logins, admin gating, per-profile saves and resume, the login screen); `lan_presence_test` covers the presence feed, chat and the client's presence model; `lan_party_test` covers 组队 (rules, following, leader-only encounters, automation gating, 队伍频道, disconnects and a game client as a member). `lan_party_battle_test` covers party battles (entering, per-slot commands and waiting, the turn timer, a lost device, escapes, 队伍共享经验 on and off against the original formula, settlement and locks per member, partial and total defeat, and a game client as a member). `lan_party_auto_test` covers LAN phase 4c (the leader's 自动练级 in a party, 自动战斗 members, the 45 s path for a manual member, refusals, stops, healing between troops, the frame budget, resume, and a game client with 快速战斗).

## Decisions (2026-09-27)

1. Movement stays client-reported in v1; `MoveIntent` validation is a later slice.
2. Paced automation waits for `presented` with a 5 s ceiling.
3. Several connections share the session; the first conflicting command wins (revised 2026-09-28 from newest-takes-control).
4. Whole-state events, no diffs: `profile` excludes storage and `pet_storage` is sent only on change. Add diffs only if parse or UI rebuild cost on Vision Pro is measured as a problem.

Differences from the first proposal: the local link replies synchronously (the `done` callback keeps call sites asynchronous-safe); GM tools are flat `gm_*` commands; troop art is checked directly instead of from a generated sprite list; the offline summary is computed by the client from the reconnect snapshot.

### Original quest dialogues

`quest_talk {npc_id}` opens an enabled source-catalog NPC. `quest_choose
{token,choice}` uses exactly the current server-issued token and one of the
returned choice ids (`yes`, `no`, `ok`). `quest_close {token}` cancels without a
profile mutation. `quest_discard {item_id}` discards one carried original item.
A successful reply contains either `dialogue {token,npc_id,name,text,choices}`
or `closed:true`. Mutations publish the normal profile event only after a
synchronous save succeeds. A failed save restores the previous profile and
returns `save_failed`. Tokens are server-owned, per backend/profile, renewed
at every phase and invalidated by movement/activity commands; a second device
opening a window replaces the first device's window. Other profiles cannot use
its token. Requests carry no client position, branch, reward or flags.

Opening and confirming require the server automation position to be on the
NPC map within Chebyshev distance 2, with no battle or automation active.
Conditions and ordered branch priority are checked again before any mutation.
ACCEPT requires YES followed by the ThanksMsg's OK before exchanging items.
REQUEST cancellation deletes all original instances named in GetItem, clears
NOW idempotently and reduces positive charm by one. CLEAN clears both NOW and
END only after confirmation. Unsupported conditions/actions fail closed.

Save version 5 adds `original_events {now:[6 uint32],ended:[6 uint32]}`,
`original_items:[positive original item IDs]`, `origin
{village_id,savepoint_bit,provenance}` and `original_savepoint_bits` (0..15).
Versions 1–4 receive empty quest flags/items and the documented Samgir prototype
origin (1000, bit 0, `prototype_default`), independently of current location.
Existing valid prototype profile data follows its existing migrations. Invalid
version 5 quest fields reject the save, with the existing validated backup
fallback; they are not repaired into an empty quest profile.

Original items are nonstack instances and consume one of 15 shared visible bag
slots each. Positive legacy inventory keys consume one visible slot, excluding
a worn copy; legacy quantities stay counted stacks. This is an explicit
prototype deviation from the original unstacked inventory. Migration never
truncates a legacy bag. New receipts exceeding 15 slots fail atomically;
ACCEPT capacity accounts for removed items before adding rewards.
# 原版木材战利品

`wild_encounter` 由服务器库存筛选原许可敌群，客户端不提供库存或奖励。
只启用已审查 enemy563：生成时原表抽取一次，结果保存在服务端 pending。
击杀接收者 claim 为服务端内部参数，不接受 RPC 指定。结算 `drop_summary`
包含 `item_id`、`received`、`name`，远端读取战斗 snapshot，经验为0也有摘要。
普通包格满时销毁物，不拒绝整场结算。许可证与事件旗标不随采木变化。
最小重启恢复覆盖单人单木；组队当前逐动作击杀者得物，合击随机名单和组队
拓扑重启恢复未实现。详见 `docs/reverse-engineering/original-wood-drops.md`。
# 任务助手与旅行

`derived.quest_helper.quests` 是服务器从原目录和角色原事件位/道具派生的任务列表。
每项含 `id`、`title`、`status`、`repeatable`、`can_restart`、`blocked_reason` 和
`steps`；步骤含稳定 `id`、`quest_id`、原 `npc_id`、`map_id`、`cell`、`label`、
`current`、`done`、`actionable`，以及可审查的原分支来源。UI 不自行判断奖励或旗标。
药草 event1/job30 的 `herb:request`、`herb:medicine`、`herb:return` 从 NOW1/END1
和2401派生；无 CLEAN 不标重做。医生 event87 与磨药来源保留但未启用，
编号原对白按序显示，确认后服务器原交易统一处理。

`quest_visit {quest_id,step_id,mode,client}` 从服务器当前步骤解析地点；兼容原
`npc_id` 参数，但不接受客户端提供落点。`mode` 为 `near` 或 `arrival`。
服务器检查忙碌、组队、当前公开目标、真实地图碰撞/占格/原门/连通性，成功设置
权威位置并返回 `target {map_id,cell,npc_id}`。客户端先下载素材，再发请求，
等待地图加载和服务器位置报告确认后走路；采木目标没有 NPC，不发起对白。
ProfileHub 绑定独立纯 `quest_visit_guard`，组队拒绝不会调用治疗钩子。
## 自动原交付任务

`quest_auto_start {quest_id,client}` 允许job11/event2、job30/event1和job1/event4；`quest_auto_stop` 停止
当前角色流程。`derived.quest_auto` 发布 running/quest_id/phase/message/target。
服务器按真实分支执行，内部限定授权调用原解释器，不开放客户端分支或奖励参数。
安全传送后等待发起设备的位置确认，再进入 talk/yes/ok，确认超时停止。
`_quest_connection` 为服务器运输层绑定标识，覆盖任何客户端字段，不能伪造。
发起连接断线停止；同角色其他设备断线不影响流程，仍可显式停止；其他角色隔离。
手动移动、组队、战斗或其他自动化停止，普通对话/旅行冲突拒绝。
停止保留已提交交易，仅清待确认 token；失败使用原同步保存回滚。
启用「重启后自动恢复」时，自动交付任务的继续意图与本次 CLEAN 授权写入
`<save>.resume.json`，与其他自动化共用周期检查点和正常停服路径。停服先保存
意图再停止 runner（包括运输层先停止的顺序）；显式停止、完成和活动冲突立即清除
意图，不能被旧检查点复活。原交易仍先同步保存角色事件位和道具。
重启只从当前持久 flags/items 重新 `select()` 原步骤，丢弃对话与 token；已交付奖励
不再发放，已完成的 CLEAN 不再重做。恢复的流程由服务器直接前往安全 NPC 落点
并继续原交易，无需旧设备登录或地图确认，不伪造连接身份；正常新发起的流程仍保留
运输层绑定的地图确认与断线停止规则。恢复仍受手动移动、组队、战斗和其他自动化
约束。ProfileHub 按角色打开各自检查点，无登录也可续跑；恢复开关关闭时不恢复。
周期意图最多滞后 10 秒；重启前已经同步提交的原交易以角色存档为准。

博士 event15/job6 与 event16/job7 的 `doctor15:*` / `doctor16:*` 包括 `request`、
`capture`、`return`，第一阶段另有原助手 `assistant`。宠物条件由服务器原PET谓词
（物种、严格等级、`original_end_event==0`、随身栏首个）派生，缓存同时跟踪宠物UID/
等级/来源与物品格数。真实捕获步骤的 `source.type=encounter` 携带原area/enemy行号，
两种 `quest_visit` 模式沿现有安全落点协议；未导入地点显示限制，不制造NPC。
`quest_talk` 和两次 `quest_choose` 都绑定同一交付UID；末次OK交换净容量、随机奖励与
NOW/END，save失败恢复整个profile。旧token不可重采奖励，UI不接收奖励指定参数。
宠物兼容可选字段 `original_end_event` 为0/1；旧宠无字段时按捕获来源保守迁移。
博士无成人仪式门槛，无CLEAN或自动执行入口。

## Random encounter helper

`no_random_encounters {enabled: bool}` saves a per-character helper preference,
published as `derived.no_random_encounters`. It can change during any activity.
During a pending battle it stays in the authoritative profile and is saved by
normal settlement, which preserves the existing prohibition on mid-battle saves.
Missing fields in older saves migrate to `false`, preserving original encounters;
non-boolean persisted values are rejected. UI uses `link.request` and reads derived
state. `field_step` checks this preference before rolling walking randomness, so
clients cannot override it with `encounter: true`. Explicit `wild_encounter`,
automatic training/hunting and NPC battles remain available. This is a project
convenience, not an original game rule.

## 原香草野外使用

沿 `use_item` 新增可选 `pet_id`：`item="original_2401"`、空UID默认自己，非空只接
随身宠物UID。未知/仓库/非字符串UID、未知道具、死亡施药者、无2401和开放/待结算
战斗拒绝，客户端不能指定回复量。审核来源 `ITEM_useRecovery_Field` 按名义体100
随机回复90～110，截断maxHP/min1，满HP仍扣一份，零HP宠物可回复。返回 `note`
报告实际回复；`SessionClient.use_item` 可选完成回调在真实回复后更新反馈，UI等待
期间阻止重复提交。所有 `use_item` 经同步保存，失败恢复profile并返回save_failed。
消费只改HP和一个2401实例，不改原任务flags或宠物PET来源；助手读服务器库存更新。
此接口不接入原战斗道具回合，不支持其他玩家/仓库目标，原道具装备元数据由独立
装备切片同步。普通 `item="potion"` 仍按旧自己回复30/满血拒绝规则。


`quest_auto_start {quest_id: 1}` runs the original adult delivery chain. Initial
helper travel explicitly bypasses the original level30 entrance; NPC REQUEST is
still LV>0. Inside10204 the server walks one original safe cell per tick, calls
field_step and pauses for the existing single-battle runner. Normal entrance
check_passage/report_position enforce level30. Server quest_position_seq receipts
match the initiating device/connection and at most16 issued positions, acknowledge
without rewinding, and never accept a different cell for that sequence.
AdultCheckpoint v1 restores only source450–453 solo battles, their exact pending
rewards/turn/RNG, and rejects already committed battle IDs; no party restoration
is included. The integrated v6 authority migrates v5 embedded profiles using
original-equipment migration and preserves validated v6 UIDs/durability.

自动交付任务共享 `quest_auto_policy.gd` 的 job/event 映射 `{1:4,11:2,30:1}`；服务端启动及resume、客户端按钮和地图下载一致校验。药草job30预下载3110/20105，复用原交易token与保存，不改变SAVE_VERSION，不开放博士捕宠自动。重新启动先按当前旗标和持有药品derive步骤，旧对白token不可恢复。

### 原版美容师对话

`quest_talk {npc_id: "original/charm/1005"}`（或 `original/charm/2005`）
打开医院美容师。`quest_choose {token, choice: "charm"}` 请求收费确认，
`leave` 退出；确认窗 `yes` 提交、`no` 退出，结果窗 `ok` 关闭。
服务器验证同地图、距离≤2格、非战斗及非自动活动，每个 token 只用一次。
客户端显示服务器台词及选项，远程客户端无 backend。费用和基础魅力重新读取
服务器存档，保存失败整体回滚，玩家参数和原版 C int 费用须有效。
可选 `player.transmigration` 默认0，只保留原版收费兼容，不提供转生玩法。

### 抓宠目标集合

`hunt.templates` 是角色自动化设置中的可选整数数组，服务端严格验证整型数值（JSON 的整数浮点表示也接受）、范围、去重并排序。显式 `[]` 表示全不选，不能开始捕获。新勾选列表经 `set_automation_settings` 保存，远程 UI 只读取 snapshot、通过 link request 修改。

旧设置及旧 `auto_start.filter.template` 继续兼容：非负值转换为单种目标，`-1` 或缺省保留旧的“当前位置全选”语义，不会迁移为空数组。旧角色首次明确勾选、全选或全不选后保存 `templates`；不增加 SaveVersion。旧调用显式发送 `template` 时覆盖集合；同时发送集合时以集合为准。切换地点保留集合，只取集合与当地实际可抓且素材齐全品种的交集，不自动补选新地点品种；交集为空时拒绝开始。

目标 UI 使用唯一可见的 `HuntTargets` 摘要，旧 `species` 下拉框只作兼容查询且始终隐藏。摘要按本地有效交集显示「全部 N 种」「未选」或「已选 N 种：中文名」；提示区分完整本地名单与保存但此处不可抓的目标，不因显示或切页改写集合。手机目标行单行省略，弹窗按窗口宽高限制、以实际字体缩短长项并保留完整 tooltip，长名单可滚动。全选／全不选菜单操作使用独立正数 ID（`TARGET_ALL` / `TARGET_NONE`）：Godot 实际点击负数 ID 时回传行号，不能靠直接发送 `id_pressed(-2/-3)` 验证真实菜单行为。品种勾选仍经角色设置请求保存，远程客户端无需 backend。

运行中取消品种会清理其排队个体并记录“未捕获·目标取消”，取消摸底待选个体；排队捕获前再次检查目标集合。已进入捕获战斗的个体完成本次战斗。恢复状态保存同一集合，空集合不可恢复捕获。原生 helper 的 `filter` 行仍兼容旧协议，其 `usable` 列表现在携带服务端计算的目标交集、`template=-1`，因此无需更改协议版本或随机抽取逻辑；库存门控、掉落随机消耗和混合敌群规则不变。

### 练级挑敌群（非原版助手）

角色设置 `training.select_troops` 为严格布尔，默认 `true`；自动练级窗口可直接切换，经 `set_automation_settings` 保存和跨设备 snapshot 同步。运行中切换从下一次进战判断生效。只有自动练级普通攻击／带宠升级及后台搜宠的真实训练阶段使用；找宠、捕获、手动、任务和 NPC 战斗均不调用筛选。已打开的首场战斗照常完成：沿用原有单场自动接手语义，完成后结束，不强制退出或改敌人。后台旧快速模式直接升级、没有训练遇敌，保持原行为。

`server/training_troops.gd` 只读当前地点的权威 `EncounterCatalog.area_at`（包括优先级遮盖）；按角色 `original_items` 验证 requires/excludes 条件，忽略零概率、无效或没有可渲染队形的组。原本就在当地表中的稀有 Lv.1 组照常评估，不引入高等级池。

评分是**在胜利且目标按现有规则参与结算时，每次可进入该组的预计经验**：敌人采用 `EncounterCatalog.experience`（原表固定经验，或 experience_table、基础模板档级及抗性/rare 修正），在原表等级闭区间均匀平均；敌群人数按实际 `1..min(area.max_enemies,Σmax_count,10)` 均匀分布。槽位按原权重抽取，重复条目累计权重和数量上限；用离散状态概率精确展开原来的100次抽取、上限拒绝和最多5只大型宠物规则。仅对可渲染且非空的实际队形取条件期望，缺素材队形仍按原进场路径跳过。

单人／镜像队出战宠每个击倒敌人获得 `reward_xp × xp_multiplier`，这是当前 `GameSession.apply_battle_result` 的真实结算规则；不凭空加阵营人数除数或单人等级差惩罚。统计实际角色／宠物人数，并保留真实目标等级；镜像不分走真实宠物经验，其他携带／仓库宠不算经验接收者。无出战宠且能确定每个击杀都有角色归属时，以坐骑经验评分；否则以角色经验评分。坐骑潜在经验单独调用 `Riding.experience`（倍率在等级差与60%取整之前），标记为“敌人由角色取得击杀归属时”，不拿不确定的坐骑击杀份额冒充目标宠物评分。LAN共享经验队伍使用真实参与名册和 `PartyBattleSession.gap_exp`；未共享经验时经验依赖未来击杀归属，当前明确暂停并提示打开共享或关闭挑群，不猜分配比例。胜负概率、宠物中途逃走／切换未计入此期望；练级保护本身不变。

设当地可进入的不同 `group_id` 数为 N，保留预计经验从高到低的前 `ceil(0.3*N)`，阈值同分全部保留（浮点数仅使用1e-12相对／1e-9绝对误差识别数值同分）。遇敌表组权重影响找多久，不改变此离散组数排名。无可进入且能得经验的组时暂停并说明原因。

估算在 `TrainingTroops.advance(1000)` 的短帧预算中续算并缓存队形分布，不抽随机数、不改变压力或生成战斗记录。原始 roll 完整生成敌人、成长和掉落后，只有组 id 未达阈值才跳过 `open_battle`；跳过不发经验/石币/物品，仍消费完整原随机流并把 encounter pressure 重置为当地 minimum。compact tick 每次最多跳过一组后让出，下一 tick 继续；素材和战斗保护仍走原路径。

可复用接口：`prepare(catalog,map_id,cell,profile,settings,clones,best_others,party_context)`、`advance(budget_usec)`、`summary()`（group_id、expected_xp、expected_enemies、enemy_counts、entry_probability、allowed、threshold、真实参与者）、`local_best_expected()`（当地组中最高条件期望），以及 `remaining_xp(actor,target_level)`（按当前 `level*30` 升级公式精确剩余经验，Lv.120封顶）。这项不创建额外遇敌池；经验估算和剩余经验接口可供后续功能复用。

### 借用高等级敌群练宠（非原版助手）

角色 `training.borrow_troops` 默认true，布尔校验沿现有协议：非布尔拒绝，null仍是标准“清除覆盖回默认”；旧flat auto_start非bool（含null）拒绝。窗口明确label/help，经link request和snapshot同步，独立于select_troops。只实际训练宠物/后台showcase训练借用；已开首场、捕获、搜宠、手动/NPC/任务不调用池。

触发严格 `remaining_xp > 5*local_best_expected`，每场重算，target cap120。当地0XP且有剩余按无限场处理。池为四个已审核原组，每场按权威item/event/art过滤后均匀抽组，直接 `EncounterCatalog.roll_group(area,group_id,rng,held)`，不从异地图普通roll误抽别组。原roll保留原组加权抽取和RNG顺序，C helper与hunt catalog不改。

权威runner调用 `Backend.prepare_training_borrow()`：完整独立roll先持久化可选v6字段training_borrow_rng的decimal-string seed/state，再返回troop与纯preview config。真实Battle core/训练policy预测按1000μs逐回合续算，实际首seed必须赢且五次至少四赢；同target uid/目标/完整角色clone/member配置/位置才允许原start_wild_battle_config和open_battle。无池、预测不能胜、配置变化或存档失败明确暂停。LAN共享接入真实member preview和gap_exp，未共享沿已有pause，不猜future kill credit。

`battle.training_borrow`携带source map/name/cell/area/group/ground_bitmap/field/texture/source_music。UI（含无backend remote）只读snapshot选择原来源地面背景，不移动角色/huntorigin；仍播原battle音乐，source环境music仅审计metadata。EXP/BATTLEGOLD和原drop白名单、claimed/replay-save不变；池没有已启用enemy563，不新发未审计物品。

resume保存池seed/state，角色最新状态优先，不回滚较旧resume，不重用预测/中断的roll。原Session按已结算battle id拒绝重复收益。旧v6可选字段迁移，不加SAVE_VERSION。[候选池审计](../reverse-engineering/training-borrow-pool.md)完整列出原文件行号、地图/组/敌人、原等级、门控、背景及实测seed场数。

共享保留规则只写 `hunt.keep_rule`：`tiers`（最高几档）、`per_tier`（每档几只）、`order`（档内排序）、`champions`（单项前几名）、`champion_stats`（攻／防／敏／血）、`auto`（找宠时自动整理）。每种的门槛勾选、最高−x、固定数值和 `conditions.*.keep` 留前名额仍独立。原生摸底筛选器收到各品种相同的规则，候选池、等待队列、自动整理和同种比较始终按同种分组。

旧存档仅在没有显式 `hunt.keep_rule` 时迁移：优先最后编辑的 `hunt.stat_species`，其次旧 `hunt.template`，再取首个含规则的有效物种，最后使用默认；不合法字段退回默认。保存和快照不再含物种级规则。旧客户端 patch 中的 `stat_filters.<id>.keep_rule` 接受但忽略，不触发迁移，不能覆盖共享设置。恢复文件中的运行设置同样迁移；抓到记录中的捕获时排名和原因保持冻结。

### Capture-only find-pet mode

`hunt.capture_only` is a strict boolean character preference, default false. Effective settings force `level_one`, `auto_capture` and `showcase` true and `train_after_capture` false while retaining the other mode's stored preferences. Only `find_pet` starts this workflow; the authority freezes `flow_capture_only` for the entire run and publishes `automation.flow.capture_only`. Edits apply on the next run. Original species filters, surveys, per-species queue bounds and round-robin dequeue are unchanged; `stop_after` is ignored for this mode.

Automation alone issues `GameSession.start_wild_battle_config(troop, clear_target, capture_only)` with its frozen flag. Pending authority config freezes `capture_only`, `capture_slots=1` and `capture_destination`: `carried` while a carried slot is available, otherwise `storage`. Settlement validates real Lv.1 actors and capacity before inventory/reward mutation. Carried captures reserve normal carried capacity, including protection against warehouse withdrawal consuming the reserved slot. Full carried rosters send only the new captured actor directly to storage, never move other pets or temporarily exceed 30, and keep scanning/queueing. Capture decisions record `where`, `destination`, `reason=full_auto_store` and the exact text `随身已满，已存仓`. Party configurations erase capture-only mode and retain the existing no-capture rule.

New captures retain their actual stats, growth seed and Lv.1/zero XP and persist boolean `capture_only` (source) plus `capture_only_untrained` (automatic tidy protection). Automatic keep-rule release, reject pruning and central automatic release protect this source until positive explicit training XP removes only the second flag; manual release and manual keep-rule selection retain their existing authority restrictions. Capture decisions freeze before inventory join and include the `capture_only` tag; projected Lv.120 statistics remain projections.

`ServerSettings.pet_storage_capacity()` reads optional `[pet_storage] capacity` from the authority's `server-settings.cfg`; 0/missing means the existing unlimited warehouse. Warehouse capacity applies only to storage destinations; carried captures work even when storage is full. Preflight and settlement use the same destination capacity check. Failed settlement publishes `settled=false`, `settlement_error` and no reward summary; automation pauses with the finished battle still open. `battle_close` retries its same authority result after capacity or save recovery. Capture-only save failure rolls back profile/UID/rewards, pending config and capture events together. Resume persists the frozen mode and reconciles an already carried or stored capture by actual actor identity and new UID once, without training or duplicate settlement.

Legacy pending capture-only config without `capture_destination` retains its original storage destination. Already stored captures keep source/protection flags and reconcile before scan preflight, with no move, duplicate UID or rewards. An unfinished capture whose pending battle was cleared on restart replays its original seed and freezes a new destination using current capacity; it never forces a pet into a full carried roster.

### 抓宠独立运行选择与保留预演

`set_automation_settings` 的 `hunt` 新增严格布尔字段 `background_search`、`show_battles`、`battle_training`、`preview_keep`（均默认true）。旧 `showcase` 存储/写入迁移为前三项，新字段优先；不提升SAVE_VERSION。候选队列为找宠流程的固定机制，状态内兼容字段 `flow.showcase` 表示使用队列，不再表示是否显示战斗；读取 `flow.background_search/show_battles/battle_training` 判断冻结的本轮运行方式，resume保存相应flow字段。原摸底计时不再运行，旧恢复状态清除计时后继续当前规则。

保留预演读取当前角色 `hunt.preview_keep` 与 `hunt.keep_rule.auto`，仅二者同时开启、非只抓不练时复用KeepRule判断；不分配UID或改写宠物。队列入队、规则变更、出队前复核，淘汰计入原1Hz总数/品种计数，详细未捕获记录原因“预计不会被保留”。客户端不计算决定，远程仅用settings RPC开关，详情仍来自pet_log。预演关闭可照常捕获培养后整理。

### 五兄弟与黄金羚羊的原任务子集

`quest_talk/quest_choose` 继续由 `original_quests.gd` 持有一次性token，新增白名单 `BATTLE`（仅NPCEnemy敌人1001/1012–1015）、`Warp` 与 `Charm`。实际源数据由 `brothers_quest_sources.json` 哈希锁定，库伊只开放 `king/event69_1` 的五个金羊分支，旧event30_5不绑定。NPC邻近为Chebyshev两格；客户端与助手共用纯几何offset，不访问backend。

`brothers_quests.gd` 从权威原敌人资料生成固定战，`session._pending.quest_guard` 冻结原胜后坐标。胜利结算把原位置和正常战斗奖励一起保存；失败恢复profile、pending、UID/捕获事件，`battle_close`可重试同一结果。成功关闭后发普通 `position` 事件，所有设备看到同一落点；失败、逃跑不触发胜后传送。守卫和任务传送沿既有组队保护要求单人。服务器未实现该守卫战的中途断电checkpoint；设备断线可重连现有权威战斗。

原组521/522要求2532/2547；只新增敌人1060的原掉落2548（概率1000/1000），沿原战利品归属/15格背包路径，背包满时原掉落销毁。包含1060的实际战斗也采用保存失败回滚与同战斗结算重试。不能由客户端提供任务奖励或胜后传送坐标。

答案纸2507–2516、水晶2517按itemset的dropatlogout列78在权威存档重载时清除；普通镜/真实之眼/钥匙保留。服务端保持角色在线运行时，断开查看设备不触发临时物清理。物品实例仍经OriginalEquipment分配单调UID。首次镜2547发enemy355，补发镜2532仅结束54；原EventNo=-1不会清掉NOW54，因此完成后还可按原分支补发2532，但不会再发宠。奖励装备保留物品和原图，属性/魔法未实现的提示由导入资料显示。

任务助手公开原对白、五层所有答案及五种守卫/奖励，不自动代选；瞬移是明确的项目便利。新增套件 `brothers_golden_quests_test`、`brothers_golden_ui_test`；后者使用真实WebSocket的无backend客户端和实际GUI点击，设置 `STONE_AGE_PROOF_DIR` 时必须使用真实renderer输出像素。

组队包含1060的保存重试：`session._pending.party_settlement`只接收服务器`party_turn`传入的个人slice及自己的drop claims，深拷贝冻结。保存失败回滚时保留这组数据，`battle_close`从同一冻结结果重试，而不是把共享party snapshot当个人结算。成功后随pending清除；反复关闭或已经消费的party push不会再次发奖。队长/成员/双方真实保存失败均覆盖，恢复后持久化结果逐字段与原个人slice一致，真实之眼只给原击杀归属者。它仍是当前服务端进程内的重试，不宣称新增组队断电恢复。
