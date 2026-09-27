# Local and dedicated sessions

Initial delivery is one Godot app with an in-process authority. Starting a game constructs the selected profile and world state, connects a local command/event adapter, then shows Samgir. No listening port, subprocess, account service or loopback token is needed for offline play.

Local mode uses the same validation as a future remote session. Commands and returned state should be value data; do not pass mutable authority objects to UI. Shut down cleanly and flush saves once persistence exists.

Later, select a separate headless startup scene through a dedicated-server export from the same project. A network adapter replaces local delivery; gameplay rules stay in `client/server/`. Separate process deployment does not imply a second codebase or Godot project.

Acceptance when that later slice is scheduled: run two clients against the headless authority, reject invalid movement, disconnect one client safely, and reconnect with a fresh snapshot. Client exports should exclude private server configuration; server exports should omit unnecessary visuals while retaining authoritative content.

Godot documents [headless execution and dedicated-server exports](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html). Verify flags and export behavior against the pinned local engine before implementing; documentation for a newer stable release is not a project upgrade.
