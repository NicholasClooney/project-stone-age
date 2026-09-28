# Original riding

## Verified artwork

`gmsv/char/char_base.c:50` supplies `ridePetTable`: mounted sprite, rider sprite, pet sprite and a historical enemy template ID. `char.c:3065` performs an exact rider/pet lookup. The resource pack contains actual combined rider-and-pet animations; Godot displays those frames directly, with their stored offsets and hit markers.

Every classic player appearance (100000 to 100235, the `RPlistMode` rows at `char_base.c:549`) rides exactly two species: one tiger colour (贝鲁卡 100327, 贝鲁伊卡 100328, 格鲁西斯 100329 or 金格萨贝鲁 100330) and one large mount per body type (布洛多斯 100351, 布林帖斯 100352, 布拉奇多斯 100353, 斯天多斯 100354 or 邦恩多斯 100396). The gold tiger is **100330**, not red tiger 100329: rider **100010 + gold tiger 100330 → composite 101006**, while 100000 rides 格鲁西斯 (101004) and 布林帖斯 (101000). Names come from the enemy template each table row cites (`gmsv/data/enemy.txt`, `enemybase.txt`). Every appearance also rides 左迪洛斯 100372 and 巴朵兰恩 100373 (红暴龙), see below.

```sh
.tools/asset-venv/bin/python tools/import_riding.py /path/to/stoneage2.5
```

The importer reads every uncommented `ridePetTable` row for those appearances (first match wins, as in the source loop) and skips riders missing from the imported player-character catalog.

左迪洛斯 100372 and 巴朵兰恩 100373 exist in the 2.5 pack only as family-leader composites: each character block of `ridePetTable` ends with commented-out rows for its leader bodies (`char_base.c:60-61`: leader 100700 + 10k rides 左迪洛斯 as 101008 + 10k, leader 100705 + 10k rides 巴朵兰恩 as 101009 + 10k). All 24 are complete (stand, walk and battle actions in every direction). Later servers let any appearance ride both with a certificate (`_NEW_RIDEPETS`, `RIDE_PET8/9`), but the per-appearance composites for that are not in the 2.5 pack. Since the game has no families, the importer gives each character's four colour variants (100000 + 20k + 0/5/10/15, the block the leader rows sit in) that character's leader composite; pairs record the art's body as `leader_body`. The rider therefore wears the leader outfit while on these two mounts.

The ignored `assets/legacy/riding/` folder then holds **148 pairs** (11 species) and their original sounds; `unavailable` lists the 28 pairs of the 7 appearances the character import skips (100080, 100095, 100100, 100140 to 100155, whose own bitmaps are broken; 100150's gold-tiger composite 101076 is also corrupt). No battle manifest is overwritten.

Not imported, by design:

- Family-leader appearances 1007xx as player characters (`_GM_METAMO_RIDE` blocks and the `#ifndef _GM_METAMO_RIDE` rows for 100710/100715): the game has no families. Their 左迪洛斯 / 巴朵兰恩 composites are used for normal appearances, above.
- `_NEW_RIDEPETS` mounts (`RideCodeMode`, `RideNoList`, `char_base.c:431-560`): each needs a learned certificate bit (`CHAR_LOWRIDEPETS`, granted by items in `item_event.c`), and the 2.5 pack lacks their per-body composites 101305 to 101400 and 1019xx; only the shared 100420/100425/100445 exist.

## Controls and eligibility

The pet window's side panel has **骑乘 · <name>** / **下骑 · <name>** for the selected pet. When that pet cannot be ridden now the button is disabled and the reason is printed under it, including which species this appearance can ride. DEV → 骑乘 dismounts, or rides the pet selected in the pet window, else the first carried pet this appearance can ride (a battling pet goes to standby first); its second entry still switches to rider appearance 100010 for the gold tiger. The riding slot (`ride_pet`) is separate from the fighting companion (`active_pet`); the mount cannot occupy both slots.

`GameSession.mount_pet` and `riding.gd can_mount` follow `char/family.c` `FAMILY_RidePet` (checked in its order) and the client's `checkRidePet` (`menu.cpp:21965`):

| Rule | Source | Reason shown |
| --- | --- | --- |
| Not during a battle | 战斗中不可骑宠！ | 战斗中不能骑乘或下骑。 |
| Not the battling pet | `CHAR_DEFAULTPET` check | 骑乘伙伴不能同时出战，请先设为待机。 |
| Not while riding another pet | `CHAR_RIDEPET != -1` returns; the client offers the ride button only when `ridePetNo < 0` | 请先下骑当前骑宠。 |
| Pet level within the learned riding level | `CHAR_LEARNRIDE`, raised by the riding teacher to 40/80/120/200 (`npc_riderman.c`) | 骑乘等级不足… (only when a saved `riding_level` exists) |
| Loyalty 100 | `CHAR_WORKFIXAI < 100` | 骑乘需要忠诚度100。 |
| Pet level at most player level + 5 | classic branch without `_RIDELEVEL` | 伙伴等级不能超过人物等级5级。 |
| Exact rider + pet composite | `ridePetTable` lookup | 此造型不能骑乘这只伙伴。可骑乘：… |

The game also refuses an unconscious mount. Transmigration (`_PET_2TRANS`) and pet equipment do not exist here. The riding-teacher quest and the configurable `RIDELEVEL` allowance (`setup.cf` RIDELEVEL=10) are not reproduced; without a saved `riding_level`, the level + 5 bound applies.

## Combat

`battle/battle_event.c:180` supplies the melee riding blends:

- Attack: 80% of rider plus 80% of mount.
- Defence: 70% of rider plus 70% of mount.
- Classic attacking agility: 50% rider plus 50% mount; reference profile uses 20%/80%.
- Defensive agility: 10% rider plus 90% mount.

Base agility remains available for source dodge/critical calculations. Combined values stay fractional until the original calculation truncates them. The classic mounted damage formula uses 5% rider vitality, while the unmounted branch uses 10%; critical bonus still uses the rider's own defence.

Damage sharing (`battle_event.c:1738`) uses each participant's original defence, floored to one: rider damage is `int(total × mount_defence / (rider_defence + mount_defence)) + 1`; mount damage is `total − rider_damage + 1`. These native rounding rules can sum to one more than the initial damage. Mount HP reaching zero clears the riding slot and returns to the unmounted battle animation at that impact.

The tiger composites emit sound 62 (`sae_12.wav`) and claw markers 10001/10101, which `oft.cpp:1108` maps to sound 254 (`sad_05.wav`); the large mounts emit 63 (`sae_13.wav`) and marker 10000 (sound 250). No weapon sprite is composited over the native mounted artwork.

A living mount receives 60% of the rider’s kill experience after the source over-level penalty (`battle.c:4773–4795`); the kill records its riding slot so switching or later dismounting cannot redirect the reward. A separate battling pet’s kill does not invent a rider-kill award. The original mounted HP bar uses pet frame26020 at player-bar offset `(20,25)` (`battlemenu.cpp:435`) and updates at impact.

Ranged riding, elemental averaging and historical family/quest unlocks remain outside this melee subset. Existing source combat profile selection is preserved.

## Verification

`riding_test.gd` checks mapping, incompatible appearances, health/loyalty/level restrictions, independent riding/battle slots, exact stat blends, damage sharing, automatic dismount and four original walking directions. `riding_battle_test.gd` checks native mounted attack clips and absence of a duplicate companion. `riding_choice_test.gd` covers the imported pairs, the rejection reasons, the pet-window button, the DEV toggle and a mounted 格鲁西斯 battle that settles mount experience. `riding_settlement_test.gd` verifies mount experience and rejects unrelated reward recipients.

Muted graphical runs write `/tmp/original-gold-tiger-riding.png` and `/tmp/original-gold-tiger-battle.png`.

### Mounted experience boundaries

The source applies no over-level reduction through a level gap of five. For larger gaps it computes `max(1, trunc(base × max(0, 20 − gap) / 15))`, then truncates 60% of that integer. A one-point intermediate reward therefore gives the mount zero XP. `BATTLE_AddExpItem` derives recipients from the attacking list; this implementation supports individual attacks and counters, not combined-party attacks.

`battle_event.c:3613–3615` exits an escaping actor without calling profit settlement. Normal completion settles living pets (`battle.c:3189–3192`); defeated mounts receive no experience. Captures are not kills. Settlement tests cover a rider kill followed by capture, capture-only completion, partial-kill escape, defeat, mount knockout, a separate pet kill, and exact threshold rounding.
