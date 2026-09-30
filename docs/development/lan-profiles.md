# LAN profiles (phase 0)

Several people play their own characters on one Mac: one headless server per profile, each with its own save, port, logs and restart-resume file. One web server serves the client and a lobby page for everyone. Background: [lan-multiplayer-study.md](../product/lan-multiplayer-study.md) (Phase 0, §2 A0 and §5).

The single-player setup is unchanged: `scripts/relaunch.sh` and `scripts/serve.sh` work as before.

## Add a profile

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

## Start and stop

```sh
scripts/profiles.sh start                 # build web, start everything, forward over Tailscale
scripts/profiles.sh start --skip-build    # reuse build/web
scripts/profiles.sh start --no-tailscale  # this network only
scripts/profiles.sh status                # which ports answer
scripts/profiles.sh stop                  # from another terminal
```

`start` stays in the foreground, like `relaunch.sh`. Ctrl-C stops every server and removes the forwards. Each backend gets `--shutdown-file=build/server-<port>.shutdown`. `stop`, Ctrl-C and the stop before a `start` all use `scripts/stop-server.sh --port=<port>` for every backend at once. Each backend saves, writes its restart-resume file, leaves the thread share and releases its save lock, so a hunt or find-pet cycle continues after the next `start`. TERM is only the fallback. Logs go to `build/profiles/<name>.log` and `build/profiles/web.log`. Set `STONE_AGE_PROFILES=<file>` to use another config (tests use this with ports away from the live server).

## Lobby

Open `https://<this Mac>.<tailnet>.ts.net:8780/lobby` (or the LAN address `serve_web.py` prints). It lists every profile with 在线／离线 and its port, and refreshes every 5 s. 「进入」 opens the web client with `?server=wss://<same host>:<profile port>`. The web server checks whether each backend port is bound on this Mac. It does not connect to the backends.

The game itself is still at `/`. Without `?server=` it connects to port 8781.

## Safeguards

- **Save lock**: a server writes `<save>.lock` (its pid) before loading the save, and refuses to start while another running Godot process holds it. The error names the holder. A lock whose process is gone is stale and is taken over, so a crash or kill needs no cleanup. `server/save_lock.gd`.
- **Shared fast hunt**: every scanning 本机极速模式 hunt on the Mac (servers and the desktop game) registers in `user://fast-hunt/active/`. This folder is the same for every checkout. The thread budget is split equally among the hunts scanning now: the remainder goes to the longest-running hunts, and every hunt gets at least one thread. When the number changes, each helper restarts from its committed roll within about 2 s, so results do not change. A crashed server's entry is ignored after 5 s. The hunt window shows 「本机极速模式 · 线程 2/4（2 人共享）」, and 开发者性能面板 shows 「极速筛选 线程 2/4（2 人共享）」. `server/fast_hunt_share.gd`.
- **摸底 with shares**: a survey counts full-CPU seconds (1/N per second while N hunts share) and ends at 120, so it lasts 2 min × N. It shows 「摸底中 剩 3:40（2 人共享）」.
- `--fast-threads=N` on `server_main.gd` fixes one server's budget. 线程数 changes are then refused on that server.

## Limits

- No login: anyone who can reach a profile's port plays that character, including GM commands.
- Players do not see each other. Parties are Phase 2+ in the study.
- Do not point the desktop game at a save a server is using. The desktop game does not check the lock.
