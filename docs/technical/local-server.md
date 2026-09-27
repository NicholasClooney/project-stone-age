# Local and dedicated sessions

Initial delivery is one Godot app with an in-process authority. Starting a game constructs the selected profile and world state, connects a local command/event adapter, then shows Samgir. No listening port, subprocess, account service or loopback token is needed for offline play.

Local mode uses the same validation as a future remote session. Commands and returned state should be value data; do not pass mutable authority objects to UI. Shut down cleanly and flush saves once persistence exists.

`scripts/serve.sh` now runs the same backend headless from this project (`client/server/server_main.gd`) behind a WebSocket adapter; gameplay rules stay in `client/server/`. It serves one controlling client at a time and keeps automation running with none. Separate process deployment does not imply a second codebase or Godot project; an exported dedicated-server build is not set up yet.

Acceptance when that later slice is scheduled: run two clients against the headless authority, reject invalid movement, disconnect one client safely, and reconnect with a fresh snapshot. Client exports should exclude private server configuration; server exports should omit unnecessary visuals while retaining authoritative content.

Godot documents [headless execution and dedicated-server exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html). Verify flags and export behavior against the pinned local engine before implementing; documentation for a newer stable release is not a project upgrade.
