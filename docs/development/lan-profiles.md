# LAN profiles

Several people play their own characters on one Mac. There are two ways to run it. Background: [lan-multiplayer-study.md](../product/lan-multiplayer-study.md) (§2 A0/A1 and §5).

| | One server, many profiles (phase 1) | One server per profile (phase 0) |
| --- | --- | --- |
| Start | `scripts/relaunch.sh --accounts=user://lan/accounts.json` | `scripts/profiles.sh start` |
| Address | one (`:8780`, backend `:8781`) for everyone | one backend port per profile, via `/lobby` |
| Login | name + PIN, remembered per device | none: whoever reaches the port plays |
| GM / developer tools | admins only | everyone |
| New characters | from the client | edit `profiles.json` and restart |
| CPU | one process: automation shares the main thread (budget divided) | a process per profile, separate cores |

**Use phase 1** by default: one address, logins, admin-only GM tools, and players see each other and chat (phase 2). Use phase 0 when several profiles run heavy GDScript automation at once (compact 自动练级, hunts without 本机极速模式) and one core is the bottleneck.

The single-player setup is unchanged: without `--accounts`, `scripts/relaunch.sh` and `scripts/serve.sh` serve `single-player.json` with no login, exactly as before.

## Phase 1: one server, many profiles

`server_main.gd --accounts=<file>` hosts every character in that accounts file (`server/profile_hub.gd`). Each character has its own `Backend`: save, save lock, automation, battle, 抓宠／放生／停止记录 and restart-resume file. A device logs into one character and then sends commands to it and receives only its events. Several devices can play the same character together, as before.

### Set up

```sh
# Optional: keep the existing single-player character as the owner (admin).
scripts/accounts.sh add Nicholas --save=user://single-player.json --admin
# Optional: add friends now, or let them create characters from the client.
scripts/accounts.sh add Alice
scripts/stop-server.sh                     # stop a running single-player server first
scripts/relaunch.sh --accounts=user://lan/accounts.json
```

- The accounts file defaults to `user://lan/accounts.json` (`scripts/accounts.sh --accounts=<file>` for another). New characters' saves go next to it: `user://lan/<id>.json`, where the id is the name when it is plain ASCII, else `p1`, `p2` and so on.
- `scripts/accounts.sh` asks for the PIN (4 to 8 digits) without echoing it. Other commands: `list`, `pin <name>` (a new PIN; every remembered device logs in again), `admin <name> on|off`, `create on|off` (may clients create characters; default on), `remove <name>` (the save stays). A running server picks up changes at the next login.
- The file keeps a random salt and the SHA-256 of `salt:PIN` per character, never the PIN, plus the hashes of up to 8 remembered device tokens.
- With no accounts file the server starts anyway; the first character created from a client is the admin.
- Stop with `scripts/stop-server.sh` as usual. Every open character records its run, saves, writes its restart-resume file and releases its lock.

### What a player sees

1. The page (or `--server=` desktop client) connects and shows 登录石器时代 with the characters on this server (管理员 marks admins, 在线 those with a device connected).
2. They click their character, type the PIN and press 登录 (or Enter). A wrong PIN shows 「PIN 不对，还可以再试 N 次。」; after 5 wrong PINs in a row the character is locked for 5 minutes.
3. Or 创建新角色: a name (up to 16 characters, Chinese is fine), the PIN twice, 创建并进入. The new character enters Samgir village, gets the three default companions and first chooses its look (新角色 · 选择外观).
4. The device remembers the login (`viewer.cfg`, per server address), so reloading, reconnecting after a drop and the next visit skip this screen. 设置 → 角色 → 切换角色（名字） forgets it and returns to the picker; the character's automation keeps running on the server.

### Rules

- **Admins**: GM commands (`gm_*`), 立即脱战, battle fixtures (`begin_battle`, `start_battle_config`, `start_wild_battle_config`, `open_battle`) and the server's 本机极速模式 线程数 are refused for other characters. Their client hides 设置 → 开发者 (GM 调试, 性能面板), and the 线程数 box is read-only. The training helper's 经验倍率 stays a player setting.
- **Automation budget**: compact 自动练级 and GDScript hunt scans each spend up to 12 ms per frame. The hub divides that among the characters using it now (`Automation.budget_share`, at least 1 ms each), so the WebSocket loop stays responsive.
- **本机极速模式**: every character is its own participant in the shared thread budget (`server/fast_hunt_share.gd`), as separate servers are in phase 0.
- **Backups**: opening an existing save (first login, or a restart) copies it to `backups/<save>@<date-time>.json` next to it; the newest 5 per save are kept (`server/save_backups.gd`).
- **Resume after a restart**: a character whose run was written down at shutdown opens when the server starts, so its hunt, find-pet cycle or 自动练级 goes on before anyone logs in.
- A character opens on its first login and stays open until the server stops, so its automation runs with nobody connected. Paced battles wait for that character's own devices only.

## Phase 2: seeing each other and 一般频道

On a phase 1 server, everyone logged in sees the other players on the same map, and can talk to them. Nothing changes for the single-player setup or phase 0 servers: they have no other players.

### What a player sees

- **Other players** walk around with their own look and mount (the original character and riding art, `scripts/remote_players.gd`), smoothly between cells, with their name at their feet in white, as the original draws it. They never block a cell, take a click or trigger anything: walking, encounters, NPCs and automation behave as if they were not there.
- **战斗中**: while one of them fights (a battle is open, or compact 自动练级 is running) the original V.S. mark (CG_VS_MARK_1A, graphic 25610) floats over their head.
- **Card**: resting the pointer on a player (or clicking one; the click still walks) shows their face, name, 等级, 骑乘 and 战斗中.
- **一般频道**: bottom left, above the classic bar. **Enter** or 说话 opens the line (up to 60 characters; Enter sends, Esc cancels; typing never walks). Everyone on the same map sees `名字：内容` in the chat lines and a speech bubble over the speaker for 5 s, the speaker too. 记录 opens the last 100 lines. The field keeps the newest 4 lines of the last minute. Sending more than 3 lines in 5 s is refused with 「说话太快了，请 N 秒后再说。」.

### How it works

- The hub reads each open profile's look, level, mount, battle state and last reported cell (`Backend.presence_state`, from `report_position`) every 150 ms and sends each connection a `presence` event with only what changed among the other players on its map (`server/presence.gd`). A full list goes out after a login, a reconnect or a map change. See [backend interface](../technical/backend-interface.md#presence-and-chat-on-a-multi-profile-server).
- The client keeps a small model (`network/presence_model.gd`): each player walks towards its last cell at the local walking pace (catching up when more than 2 cells behind, jumping when more than 8), and its facing and walking animation come from that movement.
- `say` goes to the hub, which checks it (`Presence.say`) and sends `chat` to every device on the speaker's map; the server log shows 「[名字] 一般频道：…」.
- **Bandwidth**: one walking player costs each viewer about 6 messages a second of roughly 95 bytes (`{"type":"presence","v":1,"map_id":1000,"full":false,"players":[{"id":"p1","cell":[81,90],"f":3}]}`), about 0.6 KB/s. Ten players all walking on one map is at most ~7 messages/s of about 380 bytes per viewer, ~2.5 KB/s each and ~25 KB/s for the server. Standing players cost nothing. CPU: the hub compares about players × viewers small dictionaries per tick.

### Differences from the original

- The original shows a fixed balloon icon (CG_ICON_FUKIDASI, 26500) for 1 s and the words only in the chat lines. Here the bubble shows the words, in the balloon's colours, for 5 s.
- The original keeps its chat lines on the field until pushed out; here lines older than a minute leave the field (记录 keeps them).
- Only 一般频道, and only the speaker's map. No 密语, 队伍, 家族 or 世界 channels, no 聊天表情, no name colours, no 称号 or family names over players, no 名片 or trade marks.
- Players' pets do not follow them for others; only the mount shows.
- The original's `nameOverTheHeadFlag` setting (hide names) is not there.

## Phase 0: one server per profile

### Add a profile

Copy the example once, then edit it. `profiles.json` is ignored by Git.

```sh
cp scripts/profiles.example.json profiles.json
```

```json
{
  "web_port": 8780,
  "fast_threads": 0,
  "profiles": [
    {"name": "nicholas", "title": "Nicholas", "port": 8781, "save": "user://single-player.json"},
    {"name": "alice", "title": "Alice", "port": 8782, "save": "user://alice.json"}
  ]
}
```

- `name`: letters, digits, `-` or `_`. It names the log file.
- `title`: what the lobby shows (Chinese is fine).
- `port`: the profile's backend port. Every port must be different, including `web_port`.
- `save`: optional, default `user://<name>.json`. Pet logs and the resume file sit next to it. A new save starts a new character.
- `fast_threads` (optional): the 本机极速模式 thread budget all profiles share. Omit it or use 0 to use the 线程数 setting (all cores but one when automatic).

Using 8780/8781 for the first profile keeps old bookmarks working. `profiles.sh start` then replaces a server started by `relaunch.sh`. Stop one before starting the other.

### Start and stop

```sh
scripts/profiles.sh start                 # build web, start everything, forward over Tailscale
scripts/profiles.sh start --skip-build    # reuse build/web
scripts/profiles.sh start --no-tailscale  # this network only
scripts/profiles.sh status                # which ports answer
scripts/profiles.sh stop                  # from another terminal
```

`start` stays in the foreground, like `relaunch.sh`. Ctrl-C stops every server and removes the forwards. Each backend gets `--shutdown-file=build/server-<port>.shutdown`. `stop`, Ctrl-C and the stop before a `start` all use `scripts/stop-server.sh --port=<port>` for every backend at once. Each backend saves, writes its restart-resume file, leaves the thread share and releases its save lock, so a hunt or find-pet cycle continues after the next `start`. TERM is only the fallback. Logs go to `build/profiles/<name>.log` and `build/profiles/web.log`. Set `STONE_AGE_PROFILES=<file>` to use another config (tests use this with ports away from the live server).

### Lobby

Open `https://<this Mac>.<tailnet>.ts.net:8780/lobby` (or the LAN address `serve_web.py` prints). It lists every profile with 在线／离线 and its port, and refreshes every 5 s. 「进入」 opens the web client with `?server=wss://<same host>:<profile port>`. The web server checks whether each backend port is bound on this Mac. It does not connect to the backends.

The game itself is still at `/`. Without `?server=` it connects to port 8781.

### Safeguards

- **Save lock**: a server writes `<save>.lock` (its pid) before loading the save, and refuses to start while another running Godot process holds it. The error names the holder. A lock whose process is gone is stale and is taken over, so a crash or kill needs no cleanup. `server/save_lock.gd`.
- **Shared fast hunt**: every scanning 本机极速模式 hunt on the Mac (servers and the desktop game) registers in `user://fast-hunt/active/`. This folder is the same for every checkout. The thread budget is split equally among the hunts scanning now: the remainder goes to the longest-running hunts, and every hunt gets at least one thread. When the number changes, each helper restarts from its committed roll within about 2 s, so results do not change. A crashed server's entry is ignored after 5 s. The hunt window shows 「本机极速模式 · 线程 2/4（2 人共享）」, and 开发者性能面板 shows 「极速筛选 线程 2/4（2 人共享）」. `server/fast_hunt_share.gd`.
- **摸底 with shares**: a survey counts full-CPU seconds (1/N per second while N hunts share) and ends at 120, so it lasts 2 min × N. It shows 「摸底中 剩 3:40（2 人共享）」.
- `--fast-threads=N` on `server_main.gd` fixes one server's budget. 线程数 changes are then refused on that server.

## Limits

- Phase 0 has no login: anyone who can reach a profile's port plays that character, including GM commands.
- Phase 1 logins are for friends on a LAN or tailnet: a 4 to 8 digit PIN, no email or recovery (an admin sets a new PIN with `scripts/accounts.sh pin`). Do not forward the port to the internet; movement and rewards are client-trusted.
- Players see each other and chat on phase 1 servers only (not phase 0), and cannot party yet (Phase 3+).
- Do not point the desktop game at a save a server is using. The desktop game does not check the lock.
- There is no per-character CPU view yet: 开发者性能面板 shows backend ticks only for the desktop game's own backend.
