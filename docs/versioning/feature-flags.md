# Feature flags

Use a small registry of gameplay capabilities, resolved at session startup. Do not spread string comparisons such as `version == "8.5"` across the engine.

| Candidate flag | Dependency / behavior |
| --- | --- |
| `world_movement` | Walkable map and collision definitions |
| `npc_dialogue` | NPC definitions and interaction validation |
| `battle` | Implemented battle ruleset and encounter content |
| `pets` | Pet definitions and ownership rules |
| `riding` | `pets`, allowed mounts, movement and animation support |
| `rebirth`, `clans`, `advanced_magic` | Future research and implementation; not enabled by default |

These names are proposals, not a historical availability table. A manifest must not enable an unimplemented feature. Unsupported or conflicting features fail at startup with the feature name and reason.

Presentation capabilities such as `modern_ui` or seamless transitions belong in client preferences/capabilities, not authoritative gameplay flags. The server still validates the same commands in either presentation mode.

Gate each gameplay feature at domain command validation and content loading; UI hiding alone is insufficient. Test at least one enabled path and one disabled rejection when introducing a flag.

Use typed configuration for formulas or numeric tuning rather than a boolean per variation. Hot toggles that invalidate saves or state are out of scope.
