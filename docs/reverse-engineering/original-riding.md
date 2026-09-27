# Original riding subset

## Verified artwork

`gmsv/char/char_base.c:50` supplies `ridePetTable`: mounted sprite, rider sprite, pet sprite and a historical enemy template ID. `char.c:3065` performs an exact rider/pet lookup. The resource pack contains actual combined rider-and-pet animations; Godot displays those frames directly, with their stored offsets and hit markers.

The supported gold tiger is **100330**, not red tiger 100329. Rider **100010 + gold tiger 100330 → composite 101006**. Other compatible appearances are exposed by the imported mapping. Blue brontosaurus 100352 composites are also present in the manifest, but it is not a T-rex and is not granted by the default test-pet pack. Red T-rex 100373 remains a separate pet; no mounted animation is fabricated for it.

```sh
.tools/asset-venv/bin/python tools/import_riding.py /path/to/stoneage2.5
```

The dedicated ignored `assets/legacy/riding/` pack contains 19 verified combinations and their original sounds. Pair 100150/100330 is excluded because its native bitmap data is corrupt. No battle manifest is overwritten by this importer.

## Controls and eligibility

DEV → 骑乘 offers a gold-tiger mount toggle and an explicit option to choose compatible rider appearance 100010. Receive the test pets first. The riding slot (`ride_pet`) is separate from the fighting companion (`active_pet`); the mount cannot occupy both slots. The DEV action places a selected gold tiger on standby before mounting.

Source `char/family.c:2290` requires loyalty 100, a valid learned riding level, a player/pet level bound and an exact graphic match. The implementation checks health, loyalty, appearance and the classic player-level-plus-five bound. If a saved `riding_level` exists it is enforced. The DEV starter scenario assumes learned riding capacity equal to player level plus five; the historical riding-training quest and configurable server level allowance are not reproduced.

## Combat

`battle/battle_event.c:180` supplies the melee riding blends:

- Attack: 80% of rider plus 80% of mount.
- Defence: 70% of rider plus 70% of mount.
- Classic attacking agility: 50% rider plus 50% mount; reference profile uses 20%/80%.
- Defensive agility: 10% rider plus 90% mount.

Base agility remains available for source dodge/critical calculations. Combined values stay fractional until the original calculation truncates them. The classic mounted damage formula uses 5% rider vitality, while the unmounted branch uses 10%; critical bonus still uses the rider's own defence.

Damage sharing (`battle_event.c:1738`) uses each participant's original defence, floored to one: rider damage is `int(total × mount_defence / (rider_defence + mount_defence)) + 1`; mount damage is `total − rider_damage + 1`. These native rounding rules can sum to one more than the initial damage. Mount HP reaching zero clears the riding slot and returns to the unmounted battle animation at that impact.

The gold tiger animation emits sound 62 (`sae_12.wav`) and claw markers 10001/10101. `oft.cpp:1108` maps those hit markers to sound 254 (`sad_05.wav`). No weapon sprite is composited over the native mounted artwork.

A living mount receives 60% of the rider’s kill experience after the source over-level penalty (`battle.c:4773–4795`); the kill records its riding slot so switching or later dismounting cannot redirect the reward. A separate battling pet’s kill does not invent a rider-kill award. The original mounted HP bar uses pet frame26020 at player-bar offset `(20,25)` (`battlemenu.cpp:435`) and updates at impact.

Ranged riding, elemental averaging and historical family/quest unlocks remain outside this melee subset. Existing source combat profile selection is preserved.

## Verification

`riding_test.gd` checks mapping, incompatible appearances, health/loyalty/level restrictions, independent riding/battle slots, exact stat blends, damage sharing, automatic dismount and four original walking directions. `riding_battle_test.gd` checks native mounted attack clips and absence of a duplicate companion. `riding_settlement_test.gd` verifies mount experience and rejects unrelated reward recipients.

Muted graphical runs write `/tmp/original-gold-tiger-riding.png` and `/tmp/original-gold-tiger-battle.png`.

### Mounted experience boundaries

The source applies no over-level reduction through a level gap of five. For larger gaps it computes `max(1, trunc(base × max(0, 20 − gap) / 15))`, then truncates 60% of that integer. A one-point intermediate reward therefore gives the mount zero XP. `BATTLE_AddExpItem` derives recipients from the attacking list; this implementation supports individual attacks and counters, not combined-party attacks.

`battle_event.c:3613–3615` exits an escaping actor without calling profit settlement. Normal completion settles living pets (`battle.c:3189–3192`); defeated mounts receive no experience. Captures are not kills. Settlement tests cover a rider kill followed by capture, capture-only completion, partial-kill escape, defeat, mount knockout, a separate pet kill, and exact threshold rounding.
