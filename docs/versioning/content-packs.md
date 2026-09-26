# Content packs

Pack content independently of the engine: maps, collision, sprite/animation metadata, audio, NPC/item/pet definitions, and localization. Keep simulation rules explicit rather than hiding them in presentation files.

## Proposed pack descriptor

Each pack declares a namespaced ID, exact revision, file inventory with hashes, schema/engine requirements, dependencies, exported content IDs, explicit overrides, and provenance status. Historical identifiers live in source mapping tables.

Resolve dependencies deterministically. If two packs export the same ID, fail unless the selected profile explicitly permits an override. Ordered precedence alone must not silently conceal accidental duplicate definitions. Include the effective override resolution in the profile digest.

Start with ordinary project assets. Godot resource packs/PCKs are a later packaging option; they are not required for M000. Keep logical content IDs independent of the packaging mechanism.

## Validation

- Required map spawns, portals, animation references, and audio references resolve.
- Collision and presentation revisions agree.
- Missing optional cosmetics have an explicit fallback; missing gameplay definitions block launch.
- Verify hashes before loading a downloaded/installed pack and reject path traversal in extraction/import tools.
- Treat executable scripts differently from passive content; a pack is not automatically trusted code.

Load only the selected profile's required content. Test installation/removal and cache invalidation when a pack manager is introduced. Do not build downloading/updating infrastructure before local content selection works.
