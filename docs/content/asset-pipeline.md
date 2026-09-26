# Asset pipeline

Separate raw references, conversion tools, generated assets, and runtime content. M000 may use manually prepared assets; a reusable importer is a later task justified by repeated work.

## Minimal inventory

For each source group record origin, exact revision or file hash, intended edition/region, format observations, provenance/license status, conversion command/version, and output IDs. Mark original, reconstructed, and placeholder material distinctly. Repository availability does not by itself establish permission to redistribute assets; keep unresolved material out of distributable packs until its status is resolved.

## Conversion contract

1. Preserve raw inputs without modification.
2. Decode into a neutral representation with dimensions, palettes, coordinates, frame metadata, and source IDs.
3. Validate counts, offsets, references, bounds, and collision alignment.
4. Generate Godot-ready textures/scenes/metadata plus server-readable gameplay definitions as needed.
5. Produce an import report and deterministic file hashes.

Keep source ID → canonical ID mappings versioned. Conversion should reproduce identical outputs for identical inputs and tool versions. Preserve enough metadata to revisit a decoding mistake without hand-editing every generated file.

M000 inventory: one village map/background, collision overlay, one idle/walk character set, one BGM loop, and one SFX. Record substitutions immediately rather than delaying the playable scene.

See [resource archaeology](../reverse-engineering/resources.md) for unknown formats and [pack validation](../versioning/content-packs.md) for distribution structure.
