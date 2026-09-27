# GM developer controls

Open **DEV → GM 调试** in the field or battle. Opening the panel never changes the profile. Changes affect the current save and set `gm_modified` on the profile and affected actor; this broad marker can also reflect ordinary GM leveling or healing, not just edited stats.

- Select the player or an owned pet, then **升至等级** (1–120). Only increases are accepted. Each intervening level uses normal growth, including the saved deterministic pet growth seed. Repeating the same level does not reroll growth.
- Set or add vitality / strength / toughness / dexterity **base** values. One displayed unit is 100 original fixed-point units. Derived HP, attack, defence and speed are recalculated; these inputs are not direct combat-stat overrides. Resulting base values must stay within 0–10,000 displayed units.
- Grant player allocation points (up to 100,000 cumulative GM points), or restore selected/all actors' HP. Allocation points remain spendable through the original status window.
- During battle, all level/stat/point/heal controls lock. **立即脱战** uses the normal escape animation and field return, with no XP, gold or captured pets. This also works during battle entry animation.

Authority methods live on `GameSession`: `gm_raise_level`, `gm_set_base_stat`, `gm_grant_points`, `gm_heal`. Actor index `-1` means player; nonnegative values select a pet; heal additionally accepts `-2` for everyone. Invalid/nonfinite input is rejected without mutation. `BattleSession.developer_escape` creates the normal escape settlement frame. Existing saves need no mandatory new fields; optional `gm_bonus_points` preserves granted allocation capacity.

Verification: `gm_rules_test.gd` covers deterministic level 120, idempotency, fixed-point conversion, invalid inputs, saved markers/points, battle locks and reward-free settlement. `gm_ui_test.gd` clicks real buttons, checks modal closure and battle escape animation/return. Run through `scripts/run.sh` to keep test audio muted.

## Clear GM labels

**清除所选 GM 标记** clears the selected player or real pet label. **清除全队 GM 标记** covers the player and all owned pets, not temporary battle clones. Both save immediately and reject changes during battle. This clears metadata only: levels, stats, growth, nonzero legacy offsets and inventory remain unchanged. Clearing a label does not restore natural stats or prove an unmodified history. The pet forecast ignores all-zero legacy offsets, while actual nonzero offsets still show its comparison warning.
