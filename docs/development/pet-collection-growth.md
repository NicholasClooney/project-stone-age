# Pet collection and growth forecast

The original pet list remains a five-row frame. The adjacent collection controls add categories and pages for the modern 30-pet roster. Filtering and paging retain actual roster indices, so selecting, renaming, mounting and opening details always refer to the same saved pet.

- Yellow marks the battle companion; blue `[骑]` marks the separately mounted pet.
- **骑乘选中伙伴 / 下骑** invokes the authority's original-animation and riding eligibility checks.
- Normal persistent startup grants the requested blue dragon, golden tiger and red rex once, without replacing existing pets. **DEV · 领取起始伙伴** explicitly requests the same idempotent pack; repeated requests do not duplicate already owned species.
- Detail and skill windows retain their original frames and controls.
- Character status portraits use the saved selected appearance.

## Growth calculator

**成长预估** displays the selected pet's current derived stats, base attributes, expected per-level base growth, and estimated level-120 derived stats. If the pet is already above 120, it projects its current level instead. An actual modified pet is explicitly marked **GM 已修改**; viewing the calculator does not modify anything.

The calculation uses `CHAR_PetLevelUp`'s native model: ten independent allocations among four attributes, one uniformly drawn rank factor from 51 integer values, and truncation of each base-stat increment. `pet_growth.gd` averages all 11 binomial allocation counts and all 51 factors, preserving that per-level truncation. The displayed future derived values apply the original formulas to the expected future base attributes; they are an estimate, not a promise or a replay of a pet's hidden future random draws. Legacy save offsets remain included.

The collection sidebar and calculator are modern convenience tools, not a claim that these expanded pages existed in the original UI. They keep the original list/detail art intact.

## Checks

`pet_growth_test.gd` verifies an independent exact expected value, no mutation, level boundaries and agreement with 1,000 native growth samples. `pet_collection_test.gd` exercises actual starter buttons, five-row paging, category selection with stable indices, separate battle/riding state and the rendered forecast. Test launches are muted.

## Comparing with the best possible native pet

The forecast table compares **this pet's estimated level-120 value**, **the species' theoretical per-stat upper value at that same level**, and the difference. It does not confuse the selected pet's future conditional ceiling with the best possible newborn of its species.

Source evidence:

- `gmsv/char/enemy.c`, around 1042–1075: four independent initial growth-weight rolls of −2…+2; exactly ten shared initial attribute allocations; base attributes multiplied by the species' initial coefficient.
- `ENEMY_getRank`, around 777–804: rank uses the nominal species table's total, not the varied individual weights.
- `char/char_data.c`, `CHAR_PetLevelUp`, 1200–1267: exactly ten shared allocations each level, a single rank-factor draw, and individual attribute truncation before adding to stored base stats.
- `include/char_base.h:41` defines `CHAR_MAXUPLEVEL` as 140 in this reference. **120 is the chosen comparison level, not a claim about the original maximum level.**

For each displayed derived stat independently, the calculator takes the species' +2 weight rolls and highest rank factor, then enumerates all 286 legal distributions of the ten shared allocation points. It maximizes the initial weighted attribute sum and each level's weighted increment before applying the original derived-stat division. This preserves integer truncation and never invents forty extra points by adding ten to all four attributes.

These are pointwise upper values: the HP-optimal allocation differs from the attack-, defence- and agility-optimal allocations. **One pet cannot attain all four listed ceilings simultaneously.** They describe un-reincarnated level-1-raised pets under the supported species rules; no GM bonuses or historical version extensions are included. GM/legacy offsets can place an individual above a native bound, and the table shows the excess without raising the species ceiling.

Independent fixtures: 乌力 at level120 has separate upper values HP1346/attack211/defence231/agility267; blue dragon has HP1510/attack347/defence231/agility206. The latter also exercises rank-factor5.20 truncation. Tests distinguish expected growth, individual conditional ceiling and species ceiling.
