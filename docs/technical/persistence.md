# Persistence

M000 and M001 can use disposable in-memory state. Introduce saves when there is progress worth preserving.

Begin with a versioned local save through Godot when needed. Use an atomic write/replace strategy and keep a recoverable backup. If transactional storage becomes necessary, select and pin a Godot-compatible SQLite adapter then. A remote database such as PostgreSQL is a later deployment choice; no database plugin is mandated now.

## Save contract

Store save schema revision, profile ID and digest, rules revision, required content identities, character identity, logical map/spawn, progression, inventory, pets, quest state, and a monotonic state revision. Store presentation preferences separately from gameplay saves.

Persist related rewards atomically: quest completion and its item/currency grant form one transaction. Do not serialize live scene nodes, network connections, or screen coordinates.

On load, validate the profile/content identity first. If missing or incompatible, explain which pack or migration is needed. Do not silently apply another edition's rules. Back up before explicit migrations; never overwrite the only original save on a failed migration.

First acceptance: save a changed position and one progression field, stop, reload, and recover both. Then test interrupted writes, incompatible profile, and repeated reward commands. Check duplicate grants once inventory/quests exist.
