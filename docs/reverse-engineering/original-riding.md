# Original riding

## Verified artwork

`gmsv/char/char_base.c:50` supplies `ridePetTable`: mounted sprite, rider sprite, pet sprite and a historical enemy template ID. `char.c:3065` performs an exact rider/pet lookup. The resource pack contains actual combined rider-and-pet animations; Godot displays those frames directly, with their stored offsets and hit markers.

Every classic player appearance (100000 to 100235, the `RPlistMode` rows at `char_base.c:549`) rides exactly two species from `ridePetTable`: one tiger colour (贝鲁卡 100327, 贝鲁伊卡 100328, 格鲁西斯 100329 or 金格萨贝鲁 100330) and one large mount per body type (布洛多斯 100351, 布林帖斯 100352, 布拉奇多斯 100353, 斯天多斯 100354 or 邦恩多斯 100396). The gold tiger is **100330**, not red tiger 100329: rider **100010 + gold tiger 100330 → composite 101006**, while 100000 rides 格鲁西斯 (101004) and 布林帖斯 (101000). Names come from the enemy template each table row cites (`gmsv/data/enemy.txt`, `enemybase.txt`).

## Certificate mounts

When no `ridePetTable` row matches, `FAMILY_RidePet` falls back to the `_NEW_RIDEPETS` certificate mounts (`family.c:2376-2393`): `RIDEPET_getPETindex` finds the mount's position in `RideCodeMode` (`char_base.c:500`, the same 15 mounts in the `_RIDE_CF` variant at 433), `RIDEPET_getNOindex` the rider's character row in `RPlistMode` (`char_base.c:549`), and `RideNoList[row][position]` (`char_base.c:534`, read by `RIDEPET_getRIDEno` at 630) is the composite. The row is per character, so a character's four colour variants share one composite. The 8.5 client's `anim_tbl.h:2275` table agrees for every shared mount.

| Mount (`RideCodeMode`) | Certificate | Composite for character row *c* (0 to 11) | In 2.5 |
| --- | --- | --- | --- |
| 帖拉所伊朵 100374, 玛恩摩洛斯 100358, 朵拉比斯 100362, 拉奇鲁哥 100279, 扬奇洛斯 100288, 卡达鲁卡斯 100283, 卡卡金宝 100346, 格尔格 100310 | `RIDE_PET0` to `7` | 101305 + 8*c* + position (101305 to 101400) | no |
| 左迪洛斯 100372, 巴朵兰恩 100373 | `RIDE_PET8`, `9` | 101008 / 101009 + 10*c* | yes |
| 史卡鲁 101532, 罗多克雷 101576 | `RIDE_PET10`, `11` | 1019xx, listed per row (for example 101978 / 101989 for row 0) | no |
| 奇宝 100370, 霍尔克 100369, 瑞里西尔 100904 | `RIDE_PET12` to `14` | 100425, 100420, 100445 for every row | yes |

Two consequences of the original data, kept as is:

- 左迪洛斯 and 巴朵兰恩 (红暴龙) use 101008 + 10*c* / 101009 + 10*c*, the same sprites as the commented family-leader rows (`char_base.c:60-61`: leader 100700 + 10*c* rides 左迪洛斯 as 101008 + 10*c*). Their rider wears the leader outfit. The 8.0 data has the same frames for these sprites and no client table names another composite, so there is no normal-outfit version to prefer. Pairs record the art's body as `leader_body`. A source without the certificate tables still gets these pairs from the leader rows.
- 奇宝, 霍尔克 and 瑞里西尔 draw one shared composite with the same rider whatever the player's appearance.

The mounted sprites for 101305 to 101400 and 1019xx exist only in the 8.0 data (`adrn_136.bin`, `real_136.bin`, `spradrn_115.bin`, `spr_115.bin`). Its bitmaps decode with the 2.5 decoder and palette (`PALET_1.SAP` is byte-identical to 2.5 `Palet_1.sap`): all 75,648 frames of the 180 target composites decoded, each has attack, damage, dead, stand and walk in all eight directions, and contact sheets of every row and mount showed clean art in the right colours.

```sh
.tools/asset-venv/bin/python tools/import_riding.py /path/to/stoneage2.5 --extra-source .tools/legacy/extracted/SA8.0-20260803
```

The importer reads every uncommented `ridePetTable` row for the player appearances first (first match wins, as in the source loop), then the certificate mounts, and skips riders missing from the imported player-character catalog. Composites come from the 2.5 pack when it has them and from `--extra-source` otherwise; a bitmap that both clients decode differently stops the import. Without `--extra-source` the missing certificate composites are listed in `unavailable` with a reason that names the option.

| Sources | Pairs | Species | Composites | Unavailable |
| --- | --- | --- | --- | --- |
| 2.5 only | 329 | 14 | 121 | 17 for 100100 (not a playable character), 470 whose composite only 8.0 has |
| 2.5 and 8.0 | 799 | 24 | 241 (120 from 8.0) | 17 for 100100 |

The ignored `assets/legacy/riding/` folder holds the pairs, composites, images and original sounds. Appearance 100100 stays out because its club sprite points at a missing bitmap in every known client. No battle manifest is overwritten. `manifest.json` records `certificate` (the `RIDE_PETn` number) on certificate pairs, and `extra_source` (the 8.0 files read and which composites came from them).

Not imported, by design:

- Family-leader appearances 1007xx as player characters (`_GM_METAMO_RIDE` blocks and the `#ifndef _GM_METAMO_RIDE` rows for 100710/100715): the game has no families.
- The 8.5 client's own extra certificate columns (蓝豹 100873, 金暴 100907 and composites 103262 to 103285, `anim_tbl.h:2262` and 2275): the server source this game follows does not list them.

### Certificates

The original requires the certificate bit for each mount (`CHAR_LOWRIDEPETS`, taught by the certificate items through `item_event.c:3096` `ITEM_useLearnRideCode`). The game has no certificate items, so, as with the family-leader requirement, the certificate is not required: anyone may ride these mounts subject to the rules below. The switch is `REQUIRE_RIDING_CERTIFICATES` in `client/scripts/riding.gd`; set to `true`, `can_mount` also requires the pair's `RIDE_PETn` number in `player.riding_certificates` and otherwise refuses with 尚未学会骑乘…，需要骑乘证明。 Only mounts the player already has as pets can be ridden; this change adds no pets.

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
| Exact rider + pet composite | `ridePetTable` lookup, then `RideNoList` (`family.c:2376`) | 此造型不能骑乘这只伙伴。可骑乘：… |
| Certificate (off, see above) | `CHAR_LOWRIDEPETS` bit for `RideCodeMode` mounts | 尚未学会骑乘…，需要骑乘证明。 |

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

`riding_test.gd` checks mapping, incompatible appearances, health/loyalty/level restrictions, independent riding/battle slots, exact stat blends, damage sharing, automatic dismount and four original walking directions. `riding_battle_test.gd` checks native mounted attack clips and absence of a duplicate companion. `riding_choice_test.gd` covers the imported pairs, the certificate mounts (per-character 扬奇洛斯 composites and their rules when the 8.0 data is imported, the `unavailable` entry otherwise), the rejection reasons, the pet-window button, the DEV toggle and a mounted 格鲁西斯 battle that settles mount experience. `riding_settlement_test.gd` verifies mount experience and rejects unrelated reward recipients.

Muted graphical runs write `/tmp/original-gold-tiger-riding.png` and `/tmp/original-gold-tiger-battle.png`.

### Mounted experience boundaries

The source applies no over-level reduction through a level gap of five. For larger gaps it computes `max(1, trunc(base × max(0, 20 − gap) / 15))`, then truncates 60% of that integer. A one-point intermediate reward therefore gives the mount zero XP. `BATTLE_AddExpItem` derives recipients from the attacking list; this implementation supports individual attacks and counters, not combined-party attacks.

`battle_event.c:3613–3615` exits an escaping actor without calling profit settlement. Normal completion settles living pets (`battle.c:3189–3192`); defeated mounts receive no experience. Captures are not kills. Settlement tests cover a rider kill followed by capture, capture-only completion, partial-kill escape, defeat, mount knockout, a separate pet kill, and exact threshold rounding.
