# One codebase, multiple profiles

A playable edition is the engine plus a resolved manifest, ruleset, feature set, and content packs. Do not create a source branch or duplicate client for each historical edition.

## Independent identities

| Identity | Meaning |
| --- | --- |
| Engine build | The executable implementation |
| Manifest schema | How profile configuration is interpreted |
| Profile revision | A reproducible edition configuration |
| Historical target | Build/region being reconstructed, if known |
| Ruleset revision | Simulation behavior and formulas |
| Content pack revision/hash | Specific resources and definitions |
| Modern protocol revision | Godot client/server wire contract (once networking exists) |
| Legacy adapter ID | A tested historical protocol variant |
| Presentation preferences | Classic/modern, scale, audio, accessibility |

M000 may hard-code `samgir-dev`. Add resolution once a second configuration is genuinely useful.

## Resolver contract

1. Parse and validate the manifest schema; reject unknown required fields or unsupported revisions.
2. Resolve exact pack versions and hashes, then their dependencies.
3. Validate feature dependencies and conflicts.
4. Resolve deterministic pack overrides and check every referenced definition.
5. Verify the selected ruleset and protocol are implemented.
6. Produce an immutable resolved profile and digest; use it throughout the session.

Proposed digest input: canonicalized manifest/rules revision, sorted feature set, and ordered pack identities/hashes. Exclude presentation preferences. Store the resolved result rather than trusting a mutable edition label.

Changing profiles requires ending the current session and checking save compatibility. Avoid live rule changes in a running battle/world. Add an explicit migration path for compatible saves; otherwise start a separate slot.

Historical support should be a capability matrix tied to evidence: resources, login, movement, maps, battle, pets, and saves can have different support levels.
