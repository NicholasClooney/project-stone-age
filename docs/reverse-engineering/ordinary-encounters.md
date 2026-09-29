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
- `char/enemy.c:726–774`: explicit XP overrides or base XP table plus rank/resistance modifiers. Resolver supplies this raw enemy XP; battle reward distribution remains a separate concern. Per-enemy fixed gold is zero; the server-wide battle currency rule below is applied once during settlement.
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

The game scene checks source encounter pressure after a completed non-portal wilderness step (`handle_arrival` in `client/scripts/game/game_areas.gd`). DEV forced encounters use the current ordinary region, moving to Samgir wilderness only from a safe map. The original MVP boss stays an explicit separate challenge. Missing animation troops are rejected before creating pending authority state; no replacement or reroll changes the source distribution.

`GameSession.start_wild_battle_config` preserves source actors. Capture eligibility is checked both during commands and settlement; captures retain wild level, base stats, growth rolls and source template identity. Saves validate the template and sprite, and captured companions can use the existing pet collection, growth forecast and battle flow. Ten-enemy display uses the two original rows and per-enemy targeting. Source raw enemy XP is connected to the existing MVP reward distribution; this is not a claim of full original team/level-dependent XP settlement. Captures currently restore full HP on acquisition, matching the existing MVP convention; original capture-health behavior has not been audited.

Regression suites: `wild_encounter_integration_test` (actual walking, region-provenance, escape and missing art), `wild_encounter_authority_test` (capture/save/validation), and `group_battle_ui_test` (ten mixed actors, targets, animation and removal).

Capture eligibility flags are enforced, but the existing MVP HP-threshold success rule remains; original level-difference/resistance-based capture probability is not claimed restored.

## Battle currency and remaining loot scope

The pinned server fork enables `_BATTLE_GOLD` (`gmsv/include/version.h:345`), with `BATTLEGOLD=10` in `gmsv/setup.cf:64`. `BATTLE_GetExp` (`gmsv/battle/battle.c:2902–2912`) adds **the player’s level × that factor**, before the level-up check (`:3150`). This is a configurable fork feature, not evidence that every historical official release paid cash after battles. Enemy level/count do not determine this award.

Source encounters now snapshot that pre-level-up amount and credit it once on successful win/capture settlement. Four temporary mirrors do not multiply it, and the XP assist multiplier does not affect it. The existing MVP defeat/escape policy still gives no rewards; this is not a claim of complete original retreat/stop settlement parity. Currency uses the current save-format cap (1,000,000,000), not a restoration of all original account-dependent wallet caps. Tutorial encounters retain their existing fixed rewards.

Item loot is separate and still deferred: `ENEMY_createEnemy` (`gmsv/char/enemy.c:1109–1118`) rolls enemy item probabilities against 0–999 with `_FIX_ITEMPROB`, and `BATTLE_AddExpItem` (`gmsv/battle/battle.c:4715` onwards) distributes those items. The currency fix does not fabricate item drops or sell values.

Regression: `./scripts/run.sh --script res://tests/wild_currency_test.gd` covers victory/capture, no retreat/death award, pre-level-up snapshot, clones/100× XP independence, forged/replayed rewards, save/load and the wallet cap.
