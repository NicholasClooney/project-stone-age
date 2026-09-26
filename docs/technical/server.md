# Swift server

Optimize initial implementation for macOS development, fast startup, useful logs, and easy debugging. Choose the simplest working Swift executable and transport for M001. SwiftNIO is a candidate, not a prerequisite. Python may assist research/import tools but is not required in the shipping runtime.

## First implementation

Own one map, one player session, movement validation, and authoritative position. Start with in-memory state. Add a persistence boundary only when the save slice needs it.

A single serialized simulation owner is sufficient initially. Swift actors may provide that ownership, but do not create one actor per entity by default. Avoid suspension between checking an invariant and applying its related state changes; actor isolation alone does not make a multi-step transaction atomic across awaits.

## Growth rules

- Validate session identity, command shape, map membership, movement bounds, and collision before mutation.
- Emit state changes only after acceptance; include a revision/sequence for ordering.
- Introduce map or battle owners when measured complexity requires them.
- Define transfer ownership explicitly so a player cannot be active on two maps.
- Keep transport parsing and database operations out of rule calculations.
- Inject clocks/randomness when battle and replay tests need determinism.

Record rejection reasons in development logs without dumping credentials. M001 is complete when a blocked move is rejected by Swift, accepted movement appears in Godot, and a server stop produces a recoverable client state.

Future Linux/Windows support is governed by [platform constraints](platforms.md), not by adding unused platform implementations now.
