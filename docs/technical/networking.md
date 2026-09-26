# Networking and command boundary

Modern transport and historical protocol compatibility are independent choices. Do not force the Godot client to use a legacy packet format merely to support a future legacy adapter.

## Proposed M001 transport

Use UTF-8 JSON messages over loopback TCP, framed by a four-byte unsigned big-endian payload length. Proposed initial payload cap: 64 KiB. Reject invalid lengths and malformed messages before allocating domain objects. Handle partial frames and multiple frames in one read. The framing is a project proposal, not a StoneAge protocol claim.

Handshake: client protocol revision and expected profile digest → server selected revision, resolved profile identity, session ID, and initial state. Fail clearly on incompatible protocol or content. Never silently replace gameplay rules.

| Command/event | Minimum purpose |
| --- | --- |
| `MoveIntent(sequence, direction)` | Request a logical step; client cannot supply an accepted final position |
| `PlayerState(sequence, map, position, facing)` | Accepted authoritative state |
| `CommandRejected(sequence, reason)` | Resolve a refused action |
| `Interact(target)` | Later: request an in-range interaction |
| `TransitionCommitted(id, map, spawn)` | Later: complete one server-approved map transfer |

Keep a connection lifecycle of connecting, handshaking, active, disconnected, and failed. Freeze authoritative interactions after disconnect; show reconnect/retry. On reconnect obtain a fresh snapshot before resuming input. Do not replay old item, battle, or quest commands without deduplication.

Before remote deployment, implement authentication, encrypted transport, bounded command rates/queues, and untrusted-input validation appropriate to that slice. Loopback development is not proof of public-server readiness.

Legacy codecs translate to the same command boundary only after [captured fixtures](../reverse-engineering/protocol.md) establish their behavior. Modern protocol revision, historical edition, and resource revision are separate identifiers.
