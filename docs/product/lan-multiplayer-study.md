# LAN profiles and party play: feasibility study

Status: research, 2026-09-30. No code changed. Question: can different people on one LAN (or tailnet) each play their own character against the one server, and can they group up (组队) and fight together? How much work would it take?

Short answer: **separate characters are cheap**. Two players can do it today by running two server processes. A proper in-process multi-profile server with logins is 3–5 agent-days. **Seeing each other on maps** adds about 2–4 agent-days. **Real 组队 with shared battles** is the expensive, risky part at 8–12 agent-days, because the battle engine and settlement assume one player. Sharing the machine's CPU between several players' 本机极速模式 hunts is a 0.5–1 agent-day coordinator (§5). The 五人镜像队 (clone squad) already gives us the five-player battle layout and ally scheduling, so it is a good base.

Effort is in agent-days: one agent working one focused day, tests included, as in [ideas.md](ideas.md) estimates.

## 1. Current architecture facts

### One backend, one save, one session

- `client/server/backend.gd` is a `Node` that owns exactly one of each: `var session = GameSession.new()`, `var battle = BattleSession.new()`, `battle_state`, `battle_open`, `encounter_catalog`, `encounter_rng`, `save_path`, the three pet logs, `resume_path` and `var automation = Automation.new(self)`. There is no profile or connection parameter anywhere in `handle(command)`.
- `GameSession` (`client/server/game_session.gd`) is **not a singleton**: it is a plain `RefCounted` holding one `_profile` dictionary and one `_pending` battle record. Several instances can coexist. `_init` creates a fresh character with `"profile_id":"samgir-singleplayer-v1"` for everyone.
- Save: `Backend.save()` calls `GameSession.save_game(path)`, which writes `path.tmp`, copies the old save to `.bak` and renames. The write is atomic, but nothing locks the file. `server_main.gd` and the desktop game both default to `user://single-player.json`; only comments ("do not run both against it at once") stop two writers.
- Everything else hangs off the save path, so it would **already be per profile**: `<save>.release-log.jsonl`, `.capture-log.jsonl`, `.stop-log.jsonl` (`Backend._release_log_file`) and `<save>.resume.json` (`Backend._resume_file`, 重启后自动恢复).
- Session options `clone_squad` and `experience_multiplier` are `GameSession` fields set by `_cmd_set_options`. They are not saved and they are per backend.
- Static state is only read-only caches: `Backend._map_names`, `Progression._original_templates`, `TroopArt._validation`, `AutomationSettings._defaults`, and the `FastHunt.helper_override` / `threads` test hooks. It is safe to share between backends.
- Each backend parses its own world catalog (`GameSession.world_catalog`, about 165 KB JSON) and encounter catalog (`EncounterCatalog._init`, `encounters/catalog.json`, about 1.9 MB JSON). That is fine for 3–5 profiles. It is worth moving into a static cache before going much further.

### How clients connect

See [backend-interface.md](../technical/backend-interface.md).

- The desktop game builds its own `Backend` plus a `LocalLink` (`client/scripts/game.gd` around line 277). A client started with `--server=` or a web build uses `WsLink` instead (`client/network/ws_link.gd`). The web build takes `?server=wss://host:port` from the page URL and otherwise uses `<page host>:8781` (`game_remote.gd` `_server_url`).
- `server_main.gd` reads `--port`, `--bind`, `--save`, `--tls-cert` and `--tls-key`, loads one save and adds **one** `Backend` and one `WsServer` to the tree.
- `WsServer` (`client/server/ws_server.gd`) keeps one flat `_clients` list. `_receive` passes every command to the one `backend.handle`. `_on_event` sends **every backend event to every connection**. It also sets `backend.automation.client_attached` from whether any client is connected.
- `hello` only checks the protocol and returns `full_snapshot()`. There is no identity, profile choice or password. Anyone who can reach the port controls the character and every `gm_*` command.
- Several devices on the same character is a supported feature (desktop + web + Vision Pro). Commands run one at a time and the first conflicting one wins (`_stale` replies, `TURN_COMMANDS` turn check). `report_position` carries a `client` id; the backend rebroadcasts `position` and other devices mirror the walk (`game_remote.gd` `"position"` handler, `_step_follow`).

### Broadcast

- `Backend._publish()` emits `profile` (plus `pet_storage` only when it changed) after every mutation. `_emit` queues events while a command runs, and `_flush` delivers them before the reply. Battle events are `battle_started`, `battle_turn`, `battle_state` and `battle_closed`. Automation emits `auto_status` and `auto_event`; logs emit `pet_log_changed`.
- The client keeps **one** `ClientState` (`client/network/client_state.gd`: profile, battle, automation). `world.session` and `world.battle_session` are `SessionClient` / `BattleClient` over it.

### World state

- Position is client-driven and trusted. The walking client sends `report_position` and `checkpoint` (which saves `profile.location`). The backend's only live copy is `automation.position_map` / `position_cell`, which the runners use to stop when the character moves.
- Encounters: the walking client sends `field_step` / `wild_encounter` (`game_areas.gd`, `game_battle.gd`). The backend rolls with its own `encounter_rng` and `encounter_catalog.pressure`.
- Battles: one `battle` at a time per backend. `open_battle` picks `SquadBattleSession` when `config.allies` is not empty, otherwise `BattleSession`. `GameSession.start_battle_config` / `start_wild_battle_config` snapshot the player and pets into the config and set `_pending`. `apply_battle_result` settles it into the one `_profile`.
- The battle state is **player-centric**: `player_hp`, `pet`, `pets`, `active_pet`, `ride_pet`, `potions`, `captured_species_list`, `capture_slots`, and each enemy's `defeated_by_pet_index` (`battle_session.gd`). `submit_action(action, target, pet_index)` takes one command per turn, for "the player".

### Automation

- There is **one `Automation` per backend** (`client/server/automation.gd`, about 2,000 lines): battle runner (自动练级 / 带宠升级), hunt scanning and the find-pet cycle (自动抓极品 / 后台搜宠). It reaches into the backend directly: `backend.session` about 64 times, plus `backend.battle`, `battle_open`, `encounter_catalog`, `open_battle`, `save`, `publish`. It is therefore already scoped to "this backend's character", which helps: N backends means N independent automations with no changes.
- Pacing: `client_attached` plus `presented` (wait at most `PRESENT_TIMEOUT_MSEC` 5 s for a device to finish animating). In-process work per frame is capped by `HUNT_FRAME_BUDGET_USEC` and `COMPACT_BUDGET_USEC` (12 ms each) **per backend**.
- 本机极速模式 (`client/server/fast_hunt.gd`) starts the native helper `build/fast_hunt` as a separate process. By default it uses all cores but one (`FastHunt.effective_threads`, `ServerSettings.fast_hunt_threads`). Input and status files are tagged with pid and time, so two helpers never collide on files, but they do fight for CPU.

### Per-device and per-server settings

- `user://viewer.cfg` (`client/scripts/game/game_device.gd`) holds zoom, sound, playback speed, radio station, shortcuts and minimized windows. These belong to the device and never reach the backend.
- `user://server-settings.cfg` (`client/server/server_settings.gd`) holds only `fast_hunt/threads`. It is the computer's setting, so every server process that runs from the same Godot user directory shares it.
- Automation settings and the radio library belong to the character (`profile.automation_settings`, `profile.music`), so they would move with the profile for free.

## 2. Option A: several profiles, each playing alone

Every person logs into their own character. Players do not see each other (A) or only see each other walking (B, below).

### A0: one server process per profile (works today)

```sh
scripts/serve.sh --port=8781 --save=user://nicholas.json
STONE_AGE_WEB_PORT=8790 scripts/serve.sh --port=8782 --save=user://alice.json
# Alice opens https://host:8780/?server=wss://host:8782
```

- Nothing in the code prevents this. Each process has its own `Backend`, automation, logs and resume file, and the web client already honours `?server=`.
- Each process also uses its own OS process, so GDScript automation runs on separate cores. That is a real advantage over one process (see "harder than it looks").
- Gaps:
  - `serve.sh` starts the web server every time, so the second copy needs another `STONE_AGE_WEB_PORT` or a flag to skip it.
  - All processes share `server-settings.cfg`, so every fast hunt gets the same 线程数. Two players hunting at 0 = auto oversubscribe the CPU; set 线程数 by hand (for example half the cores each).
  - No login: whoever knows the port plays that character.
  - Each headless Godot process costs its own memory, roughly a couple of hundred MB. That is fine for a handful.
  - The desktop game still uses `single-player.json` in-process. It must not point at a save that a server is serving.
- Effort: **0.5 agent-day** to make it pleasant. That means a `serve.sh --no-web` / profile list, a `profiles.cfg` → port table, a simple lobby page linking `?server=` per name, a `.lock` file per save (pid) so two processes (or desktop + server) refuse to open the same save, and a per-process `--fast-threads=` override. Risk: low.

### A1: one server, many profiles (the proper version)

What must change:

| Area | Change | Where |
| --- | --- | --- |
| Session per connection | A `ProfileHub` owns `Dictionary name -> Backend`, loads each backend lazily on first login and keeps it ticking afterwards, so automation runs with nobody connected, as today. `WsServer` keeps `peer -> profile` and routes `_receive` to that backend. | new `server/profile_hub.gd`; `ws_server.gd`; `server_main.gd` |
| Save per profile | `user://profiles/<id>.json` (+ logs, resume). On first run, migrate `single-player.json` as the owner's profile. Give each character a unique `profile_id` instead of `samgir-singleplayer-v1`. | `server_main.gd`, `game_session.gd` `_init` |
| Publish routing | Each backend's `event` signal is connected with its profile bound. `_on_event` sends only to peers logged into that profile. Multi-device on one character keeps working unchanged. | `ws_server.gd` |
| Automation per profile | Already per backend. `client_attached` must count that profile's peers, not all clients. | `ws_server.gd` `_promote` / close |
| Frame budget | N backends each spending 12 ms per frame on compact training or GDScript hunting would stall the WebSocket loop (5 × 12 ms = 60 ms per frame). Divide the budget by the number of busy backends, or round-robin one backend per frame. | `automation.gd` budgets, hub `_process` |
| Fast hunt CPU | The shared thread budget from §5 (version a): the hub divides the budget among running hunts and restarts helpers when the count changes. | `fast_hunt.gd`, `automation.gd` `_fast_process`, `server_settings.gd` |
| Login / profile picker | `hello` gains `profile` + `secret`, or a separate `login` command before any other command is accepted. A client screen before the world loads: pick or create a character (reuse `character_selection.gd` for the look), with a PIN. The device remembers its last profile and token in `viewer.cfg`. The offline banner and reconnect re-send the login. | `backend.gd` `_cmd_hello`, `ws_link.gd`, `game_startup.gd` |
| New characters | Creating a profile = a fresh `GameSession` saved under a new id. The existing new-game flow (`grant_starter_pets`, `claim_default_companions`, `set_character`) runs on it. | hub |
| Concurrent writes | One backend per profile inside one process means one writer, plus the per-save `.lock` from A0 against a second process or the desktop game. | hub, `server_main.gd` |
| GM / dev tools | `gm_*`, `set_options experience_multiplier`, `battle_escape_dev`, fixtures: allow only for profiles flagged `admin` in `profiles.cfg`. They already act only on that profile's backend. | `backend.gd` `_handle` guard |
| Server settings | 线程数 stays a server setting; only admins may change it. | `_cmd_set_fast_hunt_threads` |
| Desktop app | Keep in-process `LocalLink` for solo play. Joining the LAN server is the existing `--server=` path plus the login screen. | `game.gd` |

- Effort: **3–5 agent-days**:
  - hub + routing + per-profile saves: 1.5
  - login protocol + client picker + remembered device login: 1–1.5
  - budget sharing + fast hunt threads: 0.5–1
  - admin gating, lock, migration, tests (`remote_link_test` style with two profiles): 0.5–1
- Risk: low to medium. The domain code is already instance-scoped. The risk is CPU contention in one GDScript thread, and making sure no test seam or client assumes one profile per server.

## 3. Option B: players see each other on maps

- Server: the hub keeps each online profile's `{name, character_id, face, mounted sprite, map_id, cell, facing, in_battle}`. It already learns position from `_cmd_report_position` (today stored only in `automation.position_*`). On change it sends a `presence` event to peers of *other* profiles on the same map (`players_here` on map entry, `player_moved`, `player_left`). The same-profile `position` mirroring stays as it is.
- Client: a `RemotePlayers` node per map that creates a `LegacyActor` (`client/scripts/legacy_actor.gd`, already renders any `character_id` and the riding composite) plus `pet_follower.gd` for each other player. It steps them cell by cell like `_step_follow`, shows name labels, and shows a battle marker while `in_battle`, the way the original shows fighting players. They must not block movement or trigger encounters.
- Chat (optional): a `say` command → `chat` event to players on the same map, or everyone online, with a small log panel. The original's 对话 window and `CHAR_talkToCli` colours are the reference.
- Movement stays client-trusted, as decided on 2026-09-27; that is acceptable on a LAN among friends.
- Effort: **2–4 agent-days**: presence protocol + hub 0.5–1, client actors, labels and interpolation 1–1.5, chat 0.5–1, tests 0.5. Needs A1, because presence across processes (A0) would need a separate relay. Risk: low. Watch web/Vision Pro frame cost with several extra animated actors.

## 4. Option C: grouping (组队) and shared battles

### What the original does

`references/chenmingbiao-stone-age/gmsv/`:

- `char/char_party.c` `CHAR_JoinParty`: you join the player **in front of you** (one cell, facing). The target must not be in battle and must have the party switch on (`CHAR_ISPARTY`). A party has up to `CHAR_PARTYMAX` 5 (`include/char_base.h`). The first joiner makes the target leader (`CHAR_WORKPARTYMODE`, `CHAR_WORKPARTYINDEX1..5`), and members get "加入团队！". `CHAR_DischargeParty` handles leaving; the leader leaving disbands the party. `char/char_walk.c` makes members follow the leader's steps.
- `battle/battle.c` `BATTLE_CreateVsEnemy` → `BATTLE_PartyNewEntry` enters the leader and every party member not already fighting, each with their default pet (`BATTLE_PetDefaultEntry`), on side 0. `include/battle.h`: `BATTLE_ENTRY_MAX` 10 per side = 5 players + 5 pets, `BATTLE_PLAYER_MAX` 5.
- Turn input: each player is `BATTLE_CHARMODE_C_WAIT` until they send a command (`C_OK`). `BATTLE_CommandWait` blocks the turn until every living player on the side is `C_OK`. With `_BATTLECOMMAND_TIME`, the first command starts a 120 s timer; anyone still waiting after that is forced out of battle and out of the party ("超过时间未下指令，强迫离开战斗！"). `BATTLE_TimeOutCheck` ends the battle after `BATTLE_TIME_LIMIT` (1 h).
- Rewards: `BATTLE_AddExpItem` credits each defeated enemy's full `CHAR_EXP` to **every actor in that attack's list** (the attacker, pet or rider), reduced when the actor is more than 5 levels above the enemy (`EXPGET_MAXLEVEL` 5, `EXPGET_DIV` 15). It is not divided by party size. Dropped items go to a random attacker. `BATTLE_GetExpGold` then pays each living player and their pets separately. Our solo settlement already follows the per-pet kill-credit half of this (see [progression-formulas.md](../reverse-engineering/progression-formulas.md) "Battle reward settlement").
- Also present, and out of scope for a first cut: 助战 (`BATTLE_RescueEntry`: join a party member's running battle), 观战 (`BATTLE_WatchEntry`), PvP (`BATTLE_TYPE_P_vs_P`).

### What we have to build on

- `SquadBattleSession` (`client/server/squad_battle_session.gd`) already puts up to 4 allies and 4 ally pets beside the player: `_extend_actors` speed ordering, `_enemy_action` enemies targeting allies, ally counters in `_resolve_counter`, mounts via `riding.gd`, and per-ally damage in `_apply_member_damage`. `battle_view.gd` already draws and animates allies at actor indices 12–15 and ally pets at 16–19 (`ally_home`, `can_render_allies`, frame `ally_index`). That is exactly the original's 5 + 5 side. **The layout and scheduler are reusable.**
- What the clone squad does *not* do: allies are AI copies. `_extra_action` makes every ally attack `selected_target` (or defend during capture/escape). They have no command, no items, no capture, no escape, no pet switch, no loyalty rolls. The comment in `_attack_enemy` says kill attribution "pays only the main player's actual pets". Settlement (`GameSession.apply_battle_result`) knows one `_profile`.

### What a party battle needs

1. **Party model** in the hub: `join` (adjacent + facing + 组队 switch, max 5), `leave`, `kick`, leader transfer, disband on leader leave. Members' positions follow the leader: the server rebroadcasts the leader's path, member clients lock local walking and mirror it, reusing `_step_follow`. Encounters roll for the leader only; members' `field_step` is ignored.
2. **Battle config from several sessions**: the leader's config as today, plus `allies[i]` / `ally_pets[i]` built from each member's own `GameSession` (stats, mount, active pet, potions, capture room). Each member's session gets its own `_pending` record for the same `battle_id`, so their shops, stores and saves are refused until settlement, as they are for the solo player.
3. **Per-member commands**: a `PartyBattleSession` (subclass of `SquadBattleSession`) that stores one pending command per living player slot (attack / defend / capture / item / switch / pet command and skill / escape). It resolves the turn when all living members have sent a command or the timer fires. Each command needs `battle_id` + `turn` + `slot` (the stale check exists; the slot is new). An escape removes that member only. `_extra_action` must run the member's own command instead of auto-attack; the player's `_player_action` / `_pet_action` logic has to be generalised to "actor slot k".
4. **Timeouts and disconnects**: the original's 120 s is long for friends at a table. A 30–60 s turn timer is more practical: a missing member defends, or auto-attacks (the clone AI), and after N missed turns is dropped from the party. A disconnected member keeps auto-acting until the battle ends. Settlement still applies to their save, because the backend is loaded in the hub.
5. **Rewards and ownership**: per member, the original rule (full enemy exp to each credited attacker, level-gap reduction, no split), gold per living player, and pet exp by kill credit per member. `defeated_by_pet_index` becomes `(slot, pet)`. A capture belongs to the capturing player and uses their `capture_slots`, 抓宠记录 and keep rules. `apply_battle_result` is called per member with that member's slice of the result. A defeat sends only the dead members to the village.
6. **Client battle view**: today the command panel reads `player_hp`, `potions`, `pets` and the player at slot 0 (`battle_view.gd`, around lines 783 and 877). Each client needs a "my slot" (0 for leader, 12+k for member k): its own command bar, pet list and item count, a "等待队友…" state after sending, and turn frames animated for everyone. `presented` pacing becomes "first device of each member" or just the 5 s ceiling.
7. **Automation**: the runners assume they own the battle and the character's position. While in a party, refuse `auto_start` for members, and for the leader at first. Later option: leader-only 自动练级 with members auto-attacking.

Effort: **8–12 agent-days**:

| Part | Agent-days |
| --- | --- |
| Party model + following + leader-only encounters | 1.5–2.5 |
| Multi-session config + pending/settlement per member | 1.5–2 |
| `PartyBattleSession` command collection, per-slot actions, escape, capture ownership | 2.5–3.5 |
| Client "my slot" battle UI and waiting | 1.5–2 |
| Timeouts, disconnects, automation guards, tests | 1–2 |

Risk: **high**. The engine's player/pet fields are special-cased everywhere, settlement is single-profile, and "several people, several devices each, first command wins" has many edge cases.

## 5. Fast hunt as a shared service

Idea: every player's 自动找宠 joins one fast hunt service with its own slot. The service owns the machine's CPU and divides the threads among the players who are hunting.

### Facts that make this cheap

- **The thread count never changes results, only speed.** Every roll `i` has its own seed (`FastHunt.roll_seed(run_seed, i)`). The helper commits rolls in order through a ring of `threads × 4` chunks (`tools/fast_hunt/fast_hunt.c`, `committed_chunk`), and every report covers exactly `[START, INDEX)`.
- **Restarting is already a supported, lossless operation.** `automation.set_fast_threads` stops the helper, and on the next frame `_fast_process` relaunches it at `hunt_rolls`, the last committed roll, with counters rebased through `_fast_base`. No roll is skipped or repeated. The same path already restarts the helper whenever the thresholds change (`threshold_key()`), and in that case it first merges the survey pool with `_survey_merge(fast_hunt.peek().candidates)`.
- A restart costs a process spawn plus rescanning the uncommitted chunks, which is milliseconds.
- **Verification is per player already.** The helper only searches. A reported `hit` is re-rolled in GDScript by that player's own `Automation._scan_index`, against that player's profile, filters and 保留规则, before any battle opens. A shared service never touches a profile, so a scheduling bug can slow a hunt down but cannot give anyone a wrong pet.

### (a) Minimal: one helper per player, a coordinator divides the budget

- **Budget**: the server's 线程数 (`ServerSettings.fast_hunt_threads`), or all cores − 1 when it is 0 (`Automation.threads_used`).
- **Active hunts**: backends whose `fast_hunt.running()` is true or about to start. Hunts that are in battle, training, paused or showing a catch do not count. A find-pet cycle leaves the scan phase often, and its threads go to the others meanwhile.
- **Share**: `max(1, budget × weight / total weight)`, rounded so the shares add up to the budget. When the set of active hunts or the budget changes, every affected automation gets its new count and restarts its helper through the `set_fast_threads` path.
  - That path has to merge the survey pool with `peek()` first, as the threshold path does.
  - Rebalance at most every 2–3 s, so a cycle that flips between scanning and fighting does not thrash.
- **A1 (one process)**: the coordinator is a small object in the hub that every `Automation` asks for its thread count. The status keeps publishing `hunt.threads_used`, so the hunt window can show "3 / 11 线程（2 人在找宠）".
- **A0 (one process per profile)**: the same logic works through a registry directory, `user://fast-hunt/active/<pid>.json` (weight plus heartbeat time). Each backend refreshes its own file every second, ignores files older than 5 s (crashed servers), and computes its own share from the others. No new process is needed, and the helper binary does not change.
- **Effort**: 0.5–1 agent-day, including tests with a fake clock and a stand-in helper, as in `stat_survey_test`. **Risk: low.**

### (b) A real daemon with slots and fair scheduling

- **Design**: one long-lived `fast_hunt --serve` process that the hub starts through `OS.execute_with_pipe` or a Unix socket. Each player's hunt becomes a job (input as today, its own ring and status), and one worker pool takes chunks round-robin across jobs, weighted.
- **Gains**:
  - Rebalancing is per chunk, so there are no restarts.
  - Idle jobs cost nothing, and the CPU is never oversubscribed.
  - Weights and priorities are exact.
- **Costs**:
  - Rewrite the helper's main loop and ring for several jobs (the file is about 540 lines).
  - Add a protocol for add, remove, update-thresholds and survey pool per job.
  - Manage the daemon's lifecycle and restart it if it crashes. One crash stops every player's hunt, where today it stops one.
  - Keep the per-roll parity tests working in the new mode.
- **Effort**: 2–4 agent-days. **Risk: medium.**

### (c) Fairness policies

- **Equal share** by default. It is easy to explain, and nobody's hunt starves.
- **Weights**: an optional per-profile weight in `profiles.cfg`, admin-set, for example so the machine's owner gets 2.
  - Do not weight by mode by default. 后台搜宠 (the showcase that watches each catch train to 120) spends most of its time in capture and training battles, and while it does not scan it already takes no threads.
  - A foreground/background priority can come later if it is actually wanted.
- **Survey (摸底)** is a wall-clock window (`AutomationSettings.SURVEY_SECONDS`, 120 s, owned by the backend's `survey_clock`). With a third of the threads it sees a third of the rolls, so its picks get worse. Two ways to handle it:
  1. Give a surveying hunt a temporary weight boost (×2) during its window.
  2. Stretch its window by `full threads / my threads`, so every survey sees about as many rolls as a solo one.

  Option 2 is fairer and does not hurt the others. The backend already owns the clock, so it is a small change in `_survey_process`.
- **GDScript fallback scans** (a 每秒遇敌 rate set, or no helper) do not use helper threads. They use the backend's frame budget, which §2 shares separately.

### Recommendation

Build **(a)**: 0.5–1 agent-day.

- Do it first, even before A1: with the registry directory it also fixes today's oversubscription when two players run A0 processes and both leave 线程数 on automatic.
- Add the survey window stretch from (c).
- Keep (b) for later, if restart churn or oversubscription is actually measured with four or more concurrent hunters. The design of (a) leaves each player's verification where it is, so moving to (b) later changes only the transport.

## 6. Security and operations on a LAN

- **Accounts**: a profile name + PIN is enough among friends. Store a salted SHA-256 (Godot `HashingContext`) in `user://profiles.cfg` with an `admin` flag. After login, give a random token that the device keeps in `viewer.cfg`, so a Vision Pro does not ask again. Rate-limit wrong PINs. GM commands only for admins.
- **Transport**: TLS already works (`scripts/make-cert.sh`, Tailscale certs in `.tools/tls`, `--tls-cert/--tls-key`, `serve.sh` serves HTTPS/WSS). For friends outside the tailnet, share the node or bind `--bind=` to the LAN address. Do not port-forward to the internet: movement and rewards are client-trusted.
- **CPU**: one machine running everyone's automation.
  - With A1, GDScript work shares one thread, so budgets must be divided (§2).
  - Native fast hunt helpers need the shared thread budget from §5.
  - Compact 自动练级 for several profiles at once is the realistic heavy case. If it hurts, A0-style process separation per profile is the escape hatch.
  - The 开发者性能面板 (`tick_usec` / `tick_avg_usec` in `backend.gd`) should show per-profile ticks.
- **Backups**:
  - Saves already have `.tmp` + `.bak`.
  - Add a dated copy per profile on server start (the desktop already has `before-<tag>` copies, `game.gd` around line 436) and keep the last N.
  - Pet logs and resume files follow each save automatically.
- **Save isolation**: one hub process owns `user://profiles/`. The `.lock` stops a second server or the desktop game from opening a served save.

## 7. Recommended path

| Phase | What | Agent-days | Value |
| --- | --- | --- | --- |
| 0 | A0 polish: per-profile processes, `--no-web`, save `.lock`, a lobby page with `?server=` links, plus the §5(a) fast hunt coordinator (registry directory) and survey stretch | 1–1.5 | Friends play their own characters **this week** |
| 1 | A1: hub, per-connection profile routing, login/PIN + profile picker, create character, admin-only GM, shared frame budget, the fast hunt coordinator moved into the hub, per-profile backups | 3–4.5 | One address for everyone; the base for everything social |
| 2 | B: presence (see each other walk, ride, fight marker) + simple chat | 2–4 | Feels like the original's village |
| 3 | C-lite: 组队 and follow the leader on the map, leader-only encounters. Battles still per player, or members join as AI allies using the existing clone-squad path, with their real stats but no rewards | 2–3 | Walk together; cheap first taste of party battles |
| 4 | C-full: `PartyBattleSession` with per-player commands, timeouts, per-member settlement, capture ownership, "my slot" battle UI | 6–9 | True 组队 fights |

Total for everything is about **14–22 agent-days**. Build Phase 0 first: it gives the main wish (everyone has their own character) at almost no cost. Do Phase 1 only when a single address, logins or Phase 2 are wanted.

### What makes it harder than it looks

- **One GDScript thread.** A0 gets multiple cores for free. A1 puts every profile's automation (compact battles, GDScript hunting, the find-pet cycle) on one main thread, where each backend's 12 ms budgets add up. Shared worlds (B, C) need one process, so this has to be solved, not avoided.
- **Automation assumes one player who owns the battle and position.** `automation.position_*` comes from `report_position`, runners stop when the character moves, `client_attached` is global, and runners open and close `backend.battle` themselves. Party members must be locked out of automation.
- **Battle state and settlement are player-centric.** The fields listed in §1, `submit_action` taking one command, kill credit only for the main player's pets, and `apply_battle_result` over one `_profile`. The clone squad solves layout and turn order, not ownership.
- **Battle presentation assumes "me = slot 0".** The command bar, item count, pet switching and hover text all read the solo player's fields.
- **Movement and encounters are client-trusted.** That is fine on a LAN, but party following needs the server to become the authority for members' positions, and encounters must be rolled only for the leader.
- **Global single-profile assumptions** in names and defaults: `single-player.json`, `profile_id` `samgir-singleplayer-v1`, the web default port 8781, `server-settings.cfg` shared by every process, and one `ClientState` per client (fine, as long as a client is one profile at a time).
- **Good news**: `GameSession`, `Backend` and `Automation` are instance-scoped, logs and resume files already follow the save path, static state is read-only caches, and the multi-device design (stale commands, first-wins, turn ids) carries over directly to multi-player battles.
