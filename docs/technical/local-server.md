# Optional local / bundled server

M000 runs entirely in Godot. M001 starts a Swift executable separately during development. Later, one macOS app may bundle the client, server executable, and selected content so offline play needs no separate installation or network access.

“Embedded” initially means a bundled child process. An in-process Swift library is a future option, not a first-slice requirement.

## Launch contract

1. Choose a save/profile and a writable user-data directory outside the app bundle.
2. Spawn the bundled executable with that profile and save location.
3. Bind only to loopback on an available port; generate a per-launch connection token.
4. Return a structured ready message with port, protocol revision, and resolved profile digest.
5. Connect through the normal client command/event boundary after readiness, not after an arbitrary sleep.
6. On exit request a save and graceful shutdown; after a bounded timeout terminate only the child owned by this launch.

Track launch identity and process handle; never kill a process merely because it uses a familiar port. Surface startup errors and retain a useful log path. Prevent two server processes from concurrently writing the same save.

`LocalConnection` handles startup/stop and then uses the same wire codec as `NetworkConnection`. It must not duplicate gameplay rules. LAN hosting is a separate explicit mode, not the default local bind.

Acceptance: app restart restores state once persistence exists; clean exit leaves no owned child; occupied ports and crashes produce retryable errors; offline startup performs no required remote request. Mobile/in-process packaging remains deferred pending platform-specific investigation.
