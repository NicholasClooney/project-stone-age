# Commands and networking

Start with in-process command delivery, without a wire format. Commands carry logical IDs and values; results are accepted state/events or explicit rejections. Local delivery must not expose mutable authority objects.

| Command/result | Purpose |
| --- | --- |
| `MoveIntent(sequence, direction)` | Request a step; never submit an accepted final position |
| `PlayerState(sequence, map, position, facing)` | Present authoritative movement |
| `CommandRejected(sequence, reason)` | Resolve a refused action |
| `Interact(target)` | Validate proximity and interaction state |
| `TransitionCommitted(id, map, spawn)` | Complete one accepted map transfer |

When remote play is needed, evaluate Godot high-level multiplayer/RPC with ENet for desktop sessions. Keep domain commands independent of RPC paths and transport serialization. Do not serialize arbitrary objects from peers. Bind commands to authenticated sender identity; check lengths, rates, state and ownership on the authority. Reliable delivery alone does not provide authentication, encryption or idempotent rewards.

Handshake with protocol revision and resolved profile/content identity; reject incompatible sessions clearly. On reconnect obtain a new snapshot before accepting input. Deduplicate non-repeatable requests and do not replay stale purchases or battle actions.

The previous proposed JSON-over-loopback transport is superseded; no network implementation is required for the first local authority slice. Final remote transport/security choices belong to the remote-play implementation task.

Godot's [high-level multiplayer documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) describes its networking model. It is not compatible with the historical StoneAge protocol by default. [Legacy interoperability](../reverse-engineering/protocol.md) needs a separately verified codec and build pair.
