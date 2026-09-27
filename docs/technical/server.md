# Godot gameplay authority

Use GDScript in the existing Godot project. Start with one serialized state owner in the running app. Commands request actions; accepted results drive presentation. Never let an inventory widget or client RPC assign gold, damage, pet ownership, or quest rewards.

For each command validate actor/session identity, sequence, current state, target, distance and rules as applicable. Apply related changes together before emitting events. Avoid `await` between validation and mutation. Asynchronous resource loading must not silently advance or duplicate a gameplay transaction.

First slice: `MoveIntent(sequence, direction)` checks bounds and collision, then returns accepted position/facing or a rejection. Logical geometry is shared data; camera projection is presentation. Test blocked movement, invalid directions, repeated commands, and the unchanged playable village.

Later commands include interaction, portal entry, battle action and inventory transfer. Introduce each with its first visible feature. Keep random-number generation injectable so battle fixtures are reproducible; do not promise identical replay across engine versions without testing.

A future headless entry point constructs the same authority without loading the HUD or world visuals. Export both client and server from this project. Authority content still needs collision, spawns, encounters and rules even when textures/audio are excluded.

Public hosting also needs authentication, persistence integrity, rate limits, disconnect handling, interest management and load tests. Godot provides engine/network capabilities, not a complete MMO backend. No player-capacity estimate exists yet; measure representative maps, battles and save workloads before setting one.
