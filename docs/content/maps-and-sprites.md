# Maps, sprites, and animation

## Maps

Keep visual layers, collision, depth/occlusion metadata, portal triggers, and spawns separate. Record map dimensions, logical coordinate convention, projection, tile origin, and anchor positions. Include a source mapping for any legacy IDs.

M000 may use a flattened village background plus explicit collision. Label collision coverage as partial if only bounds and one obstacle are traced. Later conversion should replace the representation without changing canonical map/portal identities.

Check one known landmark against reference imagery, align the character's feet with walkable ground, and walk around an occluder. Validate boundaries and spawn points before expanding map area.

## Sprites and animation

Store animation state, facing direction, ordered frame IDs, per-frame duration, pivot/foot anchor, and looping behavior. Preserve palette/transparency and cropping offsets during import. Do not assume mirroring is valid for asymmetrical equipment or direction-specific art.

First controller: idle ↔ walk, preserving facing when stopped. Derive walking from actual accepted displacement, not only a held key. Use time-based playback rather than one frame per render frame.

For each imported character, inspect idle and walk in four directions against a plain background and the map. Check missing frames, edge halos, foot sliding, incorrect origins, and depth sorting. A one-frame source idle may be historically accurate later; the requested M000 animated idle may use a labeled temporary treatment.

Keep the original direction numbering in metadata and map it explicitly to client facing. Treat format details as research until a fixture and reference render agree.
