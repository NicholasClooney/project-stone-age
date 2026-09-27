# M003 — First original-resource battle

Implemented as the first checkpoint of the fun-first single-player MVP. This is a complete encounter round trip, not the full progression/pet MVP.

## Play

Launch the normal app and select **村外探险** beside the development controls. The player walks to Samgir's original west exit at (49,118), arriving on Sainas map100 at (637,493). Walk eight successful steps to encounter 乌力. Choose the original attack, defend or escape icon; commands wait for animation feedback. After victory/escape, continue at the same wilderness position. Defeat returns to the village square. **返回村庄** routes to the original return portal. M still controls mute.

## Delivered

- One bounded 96×96 crop of the original 800×800 Sainas map; original coordinate origin is retained in HUD/map readings. Boundaries are blocked rather than opening onto missing terrain.
- Verified west portal pairs from `gmsv/data/npc/genout/100warp.create`; original map geometry and collision footprints, no missing graphics in this crop.
- A GDScript `RefCounted` authority owns battle HP, turn resolution and terminal outcomes. Presentation submits commands and receives copied snapshots. World movement still uses its previous local controller.
- Original battle01 SAB terrain, command icons25100/25108/25114 and pressed states; three player appearances and 乌力100250 with attack, hurt, defeat, idle and guard animation frames.
- Original normal-battle BGM `sabgm_b0.wav`; original menu audio and verified 乌力 SPR sound73 → `sae_23.wav`. SPR10000 is a hit marker, not sound. Player frames have no verified impact sound, so none is invented.
- Exploration input blocked during battle; new encounters have an eight-step grace after return. Original village NPC, map and zoom behavior preserved.

## Deliberate prototype limits

Attack8–12, enemy5–9, player48HP/enemy32HP, guard half damage and progressively easier escape are prototype balance. Original damage, speed, element, guard and escape formulas remain research/implementation work. Encounter every eight steps and species/background choice are development defaults, not verified Sainas encounter tables. Each encounter restores starting HP; no XP, currency, drops, pet ownership or saves yet. Exploration temporarily retains the village BGM outside; battle music selection is source-verified.

Battle composition uses original assets but custom placement/status/transcript for this narrow slice; it is not a pixel-exact reconstruction of every original battle panel. Assets remain ignored local imports. Importers and provenance are tracked; raw/generated proprietary assets are not committed.

## Verification

`scripts/test.sh` includes existing movement, NPC and UI suites plus authority and battle integration suites. Checks cover original portal round trips, map coordinates, automatic encounter, movement/reset isolation, mute/BGM, win/escape/defeat, and restored village NPC. Authority tests reject invalid/terminal commands and copied-state mutation. `tools/test_import_wilderness.py` uses synthetic fixtures for bounds, collision footprints, missing graphics and malformed maps. Rendered battle captures live in ignored `artifacts/`.

## Follow-up slices (now delivered in M004)

See [M004](m004-single-player-mvp.md) for current behavior; the prototype limits above describe this earlier checkpoint.

### Original order

1. Earn XP/currency, level up, recover and save that progress.
2. Capture one pet, name it and display ownership/following.
3. Command that pet in battle and grow it through XP/one skill.
4. Add a few species with different strengths, then items/shop and one quest.

Keep one Godot project; headless/network deployment remains deferred. Do not restore every Samgir NPC before making this loop rewarding.
