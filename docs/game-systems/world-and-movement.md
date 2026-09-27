# World and movement

Represent a logical map with a stable project ID, dimensions/bounds, coordinate convention, collision data, spawns, portals, and optional encounter zones. Preserve any legacy numeric ID in a separate source mapping; do not invent historical IDs.

For `samgir-dev`, propose integer logical cells, east = +X and south = +Y. Projection into rendered pixels is client-owned. If source evidence requires a different grid or direction encoding, adapt it at import/protocol boundaries and document the mapping.

## Movement progression

M000 may use continuous local movement with four cardinal directions and simple solid geometry. Choose deterministic handling for two keys: most recently pressed cardinal direction wins. There is no diagonal speed bonus or corner cutting.

When Godot authority takes ownership, choose the movement model for the active ruleset explicitly. A grid-step prototype is acceptable for `samgir-dev`, but must not be presented as verified historical timing. Server validation checks map bounds, collision, allowed speed/rate, and player state. The client animates/interpolates accepted movement.

Keep authoritative collision geometry aligned with the imported client collision. Use the same source data or a documented deterministic conversion, and include its revision in content identity.

## Portals

Portal data names source trigger, destination map, destination spawn, optional access condition, and presentation anchor. Map transitions change logical membership once, even when both scenes remain visible. See [seamless transitions](../ui-ux/seamless-transitions.md).

Acceptance: spawn is walkable; bounds block escape; blocked movement does not tunnel at low frame rates; return portals cannot trap the player or immediately bounce them back.
