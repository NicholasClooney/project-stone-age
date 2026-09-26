# Architecture overview

## Delivery stages

```text
M000: Godot input → temporary local state → Samgir presentation

M001+: Godot → GameConnection → command boundary → Swift game state
             local or remote                     ↓
                                              persistence

Future: legacy client → build-specific adapter → same command boundary
```

Godot owns input, rendering, UI, animation, audio, resource loading, and interpolation. Swift eventually owns movement validity, map membership, characters, battle, inventory, pets, quests, and saves. A local game uses the same server rules as a remote game.

## Boundaries to introduce when needed

| Boundary | Contract |
| --- | --- |
| Presentation / simulation | Input requests an action; accepted state drives visuals |
| Transport / domain | Decode messages into typed commands; do not leak packet offsets into game rules |
| Content / code | Stable content IDs resolve through the selected profile |
| Rules / edition | Ruleset and features are resolved once per session |
| Local / remote | Share commands/events; local mode adds server process lifecycle |

For M000, direct scene references and one small player controller are sufficient. Keep temporary state identifiable so M001 can replace its owner. Do not build empty abstractions, entity frameworks, dependency injection systems, or services ahead of their first consumer.

Proposed later Swift layout: `GameServerCore` for rules/state, an executable for startup/transport, persistence adapters, and a small macOS launcher boundary. Split packages only when a concrete build or test needs the separation.

## Session identity

Resolve a profile into rules revision, feature set, ordered content hashes, and protocol revision. Record that identity in handshakes, saves, and diagnostics. Presentation settings are separate. See [version resolution](../versioning/version-system.md).
