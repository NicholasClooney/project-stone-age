# 人物魅力 and 宠物忠诚度

Rules from the pinned server `references/chenmingbiao-stone-age/gmsv/` and client `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`. Code: `client/server/loyalty.gd` (formulas), `game_session.gd` (settlement, capture, migration), `battle_session.gd` (the battle check), `battle_view.gd` (the "No!" and "Leave!" words). Tests: `client/tests/loyalty_test.gd`.

## Where the numbers live

| Value | Field | Evidence |
| --- | --- | --- |
| Charm, 0..100, new character 60 | `player.charm` (`CHAR_CHARM`) | `char/char.c:274`; clamp in `CHAR_AddCharm`, `char/char.c:5239-5246` |
| Species loyalty difficulty (modai) | `pet.modai` (`CHAR_MODAI`, stored in the pet's charm slot) | `include/char_base.h:492`; enemybase column 13 `E_T_MODAI` (`include/enemy.h:19`), copied to the pet at creation (`char/enemy.c:1069`, `char/pet.c:337`). 乌力 150, 乌力乌力 100, 蓝人龙/金虎 270, 红暴龙 300 |
| The pet's own earned part, hundredths, -10000..10000 | `pet.variable_ai` (`CHAR_VARIABLEAI`, the pet's luck slot) | `include/char_base.h:44-45,493`; `CHAR_PetAddVariableAi`, `char/char.c:5251-5258` |
| Loyalty 0..100 (shown, used) | `pet.loyalty` (`CHAR_WORKFIXAI`, recomputed, never the source of truth) | `char/char.c:2918-2943` |

The status window's ninth row is `pc.charm` (`system/menu.cpp:11680`); the pet window already had a loyalty row, now filled.

## Loyalty formula

`CHAR_complianceParameter` (`char/char.c:2918-2943`), for a pet with an owner:

```text
modai  = modai <= 0 ? 100 : modai
base   = int(owner_level × charm × 1.10 / (pet_level × modai) × 100), then at most 100
loyalty = clamp(int(base + variable_ai × 0.01), 0, 100)
```

(Plus a rebirth bonus, `(140 - owner level) / 2`, for 转生 owners; this game has no rebirth.) Examples: a Lv1 owner with charm 60 and a Lv1 乌力: 44. A Lv30 owner and a Lv1 红暴龙: the base caps at 100.

The base falls as the pet outlevels its owner; `variable_ai` makes up for it as the pet levels.

## What changes loyalty (`variable_ai`, `include/battle.h:446-457`)

| Event | Change | Evidence | Here |
| --- | --- | --- | --- |
| Caught | set to 0, then lowered so loyalty is at most 60 (`CHAR_DEFAULTMAXAI`) | `battle/battle_event.c:3435-3442`, `include/char_base.h:43` | yes, with the owner's level and charm before the battle's rewards |
| Created for the player (GM petmake) | 10000 (loyalty 100) | `char/chatmagic.c:1487` | GM发放 and the developer starter pack |
| Pet levels up | +500 (+5) per level | `battle/battle.c:3224`, `char/char.c:356` | every pet level, battle or 一键升级 |
| Kill while the pet is out | +1 (+0.01); +20 (+0.2) if the enemy's level is above the pet's | `battle/battle.c:4795-4802` | every enemy credited to the pet (`defeated_by_pet_index`), any outcome |
| The pet falls | -500 (-5), halved at owner level 10 or less | `battle/battle.c:4396-4410` | a pet with HP at the start and 0 at the end, not the mount |
| The owner falls | out pet -100 (-1), halved at owner level 10 or less | `battle/battle.c:4371-4388` | on a defeat, the pet still set as battle pet |
| Knocked flying (ultimate) | owner's pet -1000, pet -1000 | `battle/battle.c:4245-4318` | no ultimate KO in this game |
| Owner hits own pet | -200 | `battle/battle_event.c:1383-1388` | the game has no command to target your own pet |
| Healed / revived by magic in battle | +10 / +300 | `battle/battle_magic.c:273,491,639` | not applied: 恢复护符 is an assist item, not original magic |
| Loyalty food items (`忠`) | per item | `item/item_event.c:667-668` | no such items yet |

## What changes charm (`include/battle.h:441-444`)

| Event | Change | Evidence | Here |
| --- | --- | --- | --- |
| A battle levels the player up | +2, once per battle however many levels | `battle/battle.c:3175-3177` | yes |
| The player falls (normal death, PvE) | -2, -1 at level 10 or less | `battle/battle.c:4379` | on a defeat |
| The battle pet leaves in disobedience | -1 | `battle/battle_event.c:4729` | yes |
| Knocked flying | -4 (-2) | `battle/battle.c:4269` | no ultimate KO |
| Disconnect in battle | -3 | `net.c:1962` | not applicable |
| 美容院 NPC (`Charm`: +5 for `level × 10 × (charm / 3)` stone) | | `npc/npc_charm.c:220-280` | no instance of the NPC in the pinned `data/npc` (only `npcgen.template`); not placed |
| Quest NPCs, charm items, equipment `charm` modifiers | | `npc/npc_exchangeman.c:1281,1687`, `item/item_event.c:668`, `item/item.c:1404` | not yet (the mirror charm's +1 is still not wired, see `docs/development/mirror-accessory.md`) |

Charm feeds the capture score (`× charm / 50`, `battle/battle_event.c:3140`, `server/capture_rules.gd`) and every carried pet's loyalty. The pet shop's buying price also uses charm + loyalty (`npc/npc_petshop.c:601-620`); this game has no pet shop.

## In battle: `BATTLE_PetLoyalCheck`

`battle/battle.c:5723-5880`, called for each pet action (`battle/battle.c:6099`) unless its command is 待机 (WAIT) or its side was ambushed. `Rand = RAND(1, 100)`:

| Loyalty | Result |
| --- | --- |
| 80 or more | obeys |
| 70-79 | Rand < 10: random target |
| 60-69 | Rand < 20: random target |
| 50-59 | Rand < 35: random target |
| 40-49 | Rand < 50: random target |
| 20-39 | Rand < 70: random action (`BATTLE_PetRandomSkill`, `battle/battle.c:5640`: a random one of seven skill slots at a random enemy) |
| 10-19 | Rand < 80: attacks its owner; otherwise attacks a random enemy |
| below 10 | Rand < 60: attacks its owner; otherwise leaves the battle (`BATTLE_LostEscape`, `battle/battle_event.c:4703`: it is recalled, not lost, and the owner loses 1 charm) |

A random target with a guard (or a command aimed at itself) becomes no action. Any disobedience also blocks a combo (`battle/battle.c:4209,6198`); there are no combos here. The server sends `BX` and the client plays `ATT_NIX`: the pet shakes its head under a "No!" (`oft/oft.cpp:5713,9930`, `CG_ICON_NO` 26509); a leaving pet shows "Leave!" (`CG_ICON_LEAVE` 26513, `systeminc/anim_tbl.h:1870,1874`). `tools/import_faces.py` imports both words into `battle/ui`.

Riding needs loyalty 100 (`char/family.c:2300`), which `scripts/riding.gd` already checked.

### Differences here

- **The roll is drawn only below 80**, where it matters, so battles with loyal pets replay exactly as before.
- Random action uses our pet's slots in the pet window's order: 待机, 攻击, 防御, then learned skills; an empty slot (up to seven) is no action, as in the source. A random 防御 does nothing this round.
- **Automated battles** (自动练级, 带宠升级, the capture battles and training of 后台搜宠: `backend.battle.automated`, set by `server/automation.gd` before each command) keep the check, but any disobedience only costs the pet its action. A pet never attacks its owner or leaves during a run, so a run is never ended by its own pet. Clone companions (分身) are copies and always obey. A battle the player takes over obeys the full rules again.
- Pets a test or tool builds without `variable_ai` keep obeying until the save is loaded (and migrated).

## Save migration (no `SAVE_VERSION` change)

- **Charm**: a player without `charm_rules` had the flat 60. They get +2 per level already gained, capped at 100 (a Lv21 or higher character has 100), and `charm_rules = 1`. Past defeats are not reconstructed.
- **Pets**: a pet without `variable_ai` gets what a pet **caught at Lv1 by this character and levelled to its current level** would have: the capture start (at most loyalty 60) plus 5 per level gained, clamped. Consequences:
  - pets of Lv29 and above (so every pet trained to 120) have +100 and loyalty 100: nothing changes for them, riding included;
  - Lv1 pets (hunt stock) have loyalty 60 or their formula value if lower, exactly like a new catch;
  - a pet from the developer starter pack (which carried `loyalty: 100`) keeps 100.
- The original would have given pets caught at higher levels less (they gain fewer levels after capture), but the capture level was never saved; assuming Lv1 is the gentlest reading and never leaves a trained pet disobedient.
- A pet that is currently ridden stays mounted even if it no longer has 100; only mounting again checks it.

## Left out

Ultimate knock-outs, 转生, the 美容院 NPC (not placed in the pinned data), loyalty and charm items, equipment charm, pet shops, pet mail. The original also gives win loyalty to every participating pet; here only the battle pet (the one that gets the kill's experience) takes part.
