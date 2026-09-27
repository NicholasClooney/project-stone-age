# Original progression formulas

## Restored rules

Pinned `references/chenmingbiao-stone-age/gmsv/char/char.c` (`CHAR_initcharWorkInt`, lines 2855–2910) stores four base attributes in hundredths. Derived values truncate only after the complete expression:

- HP: `4V + S + T + D`
- Attack: `S + 0.1T + 0.1V + 0.05D`
- Defence: `T + 0.1S + 0.1V + 0.05D`
- Agility: `D`

The implementation uses integer numerators to avoid floating-point drift. Spending a point adds 100 to the relevant stored attribute. Displayed base values divide by 100. Fractional cross-stat contributions accumulate; one point need not immediately change every affected displayed value. Three allocation points per earned level remain the source default (`battle.c`, around line 3173).

New characters use the legal 20-point allocation V9/S7/T0/D4: 47 HP, 8 attack, 1 defence, 4 agility. This is a project-selected preset, not a claim that every original character started with these numbers. A character-creation allocation screen is not implemented.

Club item 100 (`data/itemset.txt`, row 101) adds 4 attack after base derivation. Status and combat use the same effective-stat API; the underlying unequipped attack remains unchanged.

## Species and pet growth

`data/enemybase.txt` rows 1–3 define the supported species:

| Species | Initial multiplier | V/S/T/D growth weights |
|---|---:|---|
| 乌力 | 10 | 20/12/15/25 |
| 乌力乌力 | 20 | 22/23/11/23 |
| 乌力斯坦 | 15 | 22/17/19/17 |

Generation follows `char/enemy.c`, `ENEMY_createEnemy` around lines 1036–1081: each growth weight varies by −2…+2, ten additional points distribute randomly among the four initial attributes, and the initial multiplier produces hundredths. Rank thresholds follow `ENEMY_getRank` (100/95/90/85/80/0).

Pet growth follows `char/char_data.c`, `CHAR_PetLevelUp`, lines 1200–1267: distribute ten points, draw a rank-specific factor (4.50–5.00 through 5.50–6.00), add each truncated result to the stored base attribute, and recompute derived values. Per-pet seeds and level-derived draws make continuation repeatable after reload. This preserves the source distribution, not its global C random-number stream.

Normal adventure enemies are level 1; the quest enemy is level 3. These encounter levels are deliberate project content choices. Wild-enemy generation uses the original `initial + (level − 1) × 4.5` multiplier; owned pets advance through the separate per-level growth routine.

## Save migration

Save version 2 stores base attributes and pet growth metadata. Version 1 retains levels, XP, allocations, remaining allocation budget, equipment, current HP, pet identity and all earned derived stats. A named `legacy_stat_offset` preserves pre-formula strength while future gains use the source equations. Migration is deterministic and does not refund spent points or reroll pets on reload. Malformed base/growth metadata is rejected. Existing saves are backed up by the regular atomic save process.

## Remaining scope

XP thresholds/rewards still use the small adventure progression curve (`30 × level`), not original experience tables. Level-up healing, minimum nonzero speed/attack/HP, capture level reset, battle encounter selection and the old-save compatibility offsets are project policies. Character creation, reincarnation, loyalty, elemental derivation and broader equipment effects are not claimed restored by this slice.

Verification: `client/tests/progression_test.gd` checks independently calculated coefficients, fractional truncation, equipment, species differences, repeatable growth and idempotent legacy migration; existing authority/quest tests exercise actual battle rewards and allocation.

## Battle reward settlement

The active living pet at each enemy defeat accrues that enemy's reward, including counterattack defeats. Switching or withdrawing later does not transfer those points to another pet. At settlement, surviving pets receive their own accrued rewards; dead pets do not (`battle.c`, `BATTLE_AddExpItem` around 4769 and `BATTLE_GetExpGold` around 3190). The simplified adventure XP amounts remain explicit content values.

Capturing an enemy gives no kill XP/gold. Mixed capture-and-kill groups reward only defeated enemies and preserve captured pets. Escape forfeits accrued XP/gold: the PvE escape path calls `BATTLE_Exit` directly without `BATTLE_GetProfit` (`battle_event.c`, 3607–3614). Defeat pays none because `BATTLE_GetExpGold` returns for a dead player. Captured pets remain owned, consistent with acquisition before battle exit.

`battle_settlement_test.gd` drives actual three-enemy battle actions through switching, withdrawal, partial kills followed by escape/defeat, last-slot capture, mixed capture rewards and replay rejection. These tests use controlled combat strength to isolate settlement; the separate journey and balance tests use normal adventure stats.
