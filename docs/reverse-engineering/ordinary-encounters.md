# Ordinary wild encounters

## Rebuild local original data

Run from the project root after importing the world:

```sh
python3 tools/import_encounters.py
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
```

Outputs remain under ignored `client/assets/legacy/encounters/` and the existing ignored battle art directory. Catalog records preserve source IDs/line numbers; SHA-256 values identify the four input tables. `art-coverage.json` reports valid sprites and original resource failures. Never replace a missing species with a different animal or remove its weight from a regional distribution.

## Source rules

Pinned `references/chenmingbiao-stone-age/gmsv`:

- `char/encount.c:380`: inclusive rectangle boundaries (`util.c:1363`), highest strictly positive z-order; first source row wins ties. This matters where safe/village areas overlap broader regions.
- `char/char_walk.c:493–559`: clamp persistent encounter pressure to regional minimum/maximum; compare a uniform integer 0–119 against pressure; increase after a missed roll and reset to the regional minimum on a hit. Portal steps suppress encounter. Anti-encounter equipment and server-configured encounter multipliers are deferred.
- `char/enemy.c:1270–1481`: weighted group then weighted enemy choice; uniform troop size from 1 to the smaller of regional cap and sum of enemy caps. Respect duplicate per-type caps, 100-attempt limit, and up to five large enemies in the first row.
- `char/enemy.c:1030–1075`: choose level from the original inclusive range, perturb each species weight by −2…+2, distribute ten shared points, multiply by initial-plus-wild-level factor. Wild enemies do **not** use repeated domesticated-pet level-up growth.
- `char/enemy.c:295`: table fields use C `atoi`; the reference `4.50` wild-growth field becomes **4** in this compiled branch. Catalog retains both parsed and raw values. Do not silently use 4.5 while claiming parity with this branch.
- `char/enemy.c:726–774`: explicit XP overrides or base XP table plus rank/resistance modifiers. Resolver supplies this raw enemy XP; battle reward distribution remains a separate concern. No invented fixed gold reward.
- `battle/battle_event.c:3115`: enemy capture flag controls capturability; preserve the actual generated animal on capture instead of replacing it with a new level-one pet.

## API and boundary

`server/encounter_catalog.gd`: `area_at(map, cell)`, `step(map, cell, rng, is_portal)`, `roll(map, cell, rng)` and `actor(enemy_id, rng)`.

`GameSession.start_wild_battle_config(troop)` accepts the resolver result and keeps the existing player, fighting pet and mount setup. Battle authority retains all ten enemy slots and checks each enemy’s capture flag. Successful captures keep source level, base stats and growth rolls; save validation checks the original template and sprite. `Progression.species_definition` resolves both prototype names and `original_<templateID>` companions.

`roll` returns area/group IDs and full enemy actors with source IDs, original sprite, level, base/derived stats, growth weights/rank, capture flag and raw XP. Unknown coordinates never fabricate an encounter. Gate unrenderable troops at integration, preserving the source table rather than redistributing probabilities.

The pinned data itself has missing probabilities: areas 41/42/43 and groups 125/141 affect currently loaded maps. These selected records fail closed with a diagnostic; no guessed weights or silent redistribution. Explicit zero weights remain valid and still contribute source troop-cap accounting.

Quest/event-conditioned areas and item-conditioned groups are explicitly deferred. Random dojo enemy substitutions, special tactics/skills, item drops and dungeon-specific logic are not restored here. Imported table coverage is broader than gameplay coverage; do not present the presence of a table row as a playable completed area.

## Verification

- `python3 -m unittest discover -s tools -p test_import_encounters.py`
- `./scripts/run.sh --headless --script res://tests/encounter_catalog_test.gd` (muted)
- `./scripts/run.sh --headless --script res://tests/wild_encounter_authority_test.gd` (capture persistence, invalid capture/save rejection and ten-enemy roster)

Checks include original IDs/weights/levels, inclusive boundaries and overlap precedence, safe villages, 200 generated troops, shared spawn allocation and regional pressure bounds. Art import validates six combat actions in all eight directions and decodes every referenced image before accepting a sprite.

## Integrated gameplay scope

`game.gd` checks source encounter pressure after a completed non-portal wilderness step. DEV forced encounters use the current ordinary region, moving to Samgir wilderness only from a safe map. The original MVP boss stays an explicit separate challenge. Missing animation troops are rejected before creating pending authority state; no replacement or reroll changes the source distribution.

`GameSession.start_wild_battle_config` preserves source actors. Capture eligibility is checked both during commands and settlement; captures retain wild level, base stats, growth rolls and source template identity. Saves validate the template and sprite, and captured companions can use the existing pet collection, growth forecast and battle flow. Ten-enemy display uses the two original rows and per-enemy targeting. Source raw enemy XP is connected to the existing MVP reward distribution; this is not a claim of full original team/level-dependent XP settlement. Captures currently restore full HP on acquisition, matching the existing MVP convention; original capture-health behavior has not been audited.

Regression suites: `wild_encounter_integration_test` (actual walking, region-provenance, escape and missing art), `wild_encounter_authority_test` (capture/save/validation), and `group_battle_ui_test` (ten mixed actors, targets, animation and removal).

Capture eligibility flags are enforced, but the existing MVP HP-threshold success rule remains; original level-difference/resistance-based capture probability is not claimed restored.
