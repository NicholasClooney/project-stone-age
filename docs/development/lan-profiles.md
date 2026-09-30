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

**Use phase 1** by default: one address, logins, admin-only GM tools, and it is the base for seeing each other later. Use phase 0 when several profiles run heavy GDScript automation at once (compact 自动练级, hunts without 本机极速模式) and one core is the bottleneck.

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
- Players do not see each other yet (Phase 2) and cannot party (Phase 3+).
- Do not point the desktop game at a save a server is using. The desktop game does not check the lock.
- There is no per-character CPU view yet: 开发者性能面板 shows backend ticks only for the desktop game's own backend.
