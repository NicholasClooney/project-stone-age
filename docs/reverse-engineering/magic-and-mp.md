# 精灵 (magic) and 气力 (MP)

Rules from the pinned server `references/chenmingbiao-stone-age/gmsv/` (GBK; paths below are relative to it) and the 8.5 client `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`. Code: `client/server/spirits.gd` (data and formulas), `game_session.gd` (气力, equipment, field casts, settlement), `battle_session.gd` (the battle cast), `party_battle_session.gd` (members' casts and their screens), `scripts/battle_auto_policy.gd` (`spirit_choice`, 用精灵补血), `automation.gd` and `profile_hub.gd` (`_party_guard`). Tests: `client/tests/spirits_rules_test.gd`, `spirits_party_test.gd`, `spirits_ui_test.gd`.

## 气力

| Rule | Evidence | Here |
| --- | --- | --- |
| A new character has `CHAR_MAXMP = CHAR_MP = 100` | `char/char.c:275` | `player.mp`, `Spirits.MAX_MP` 100 |
| Max 气力 is `CHAR_MAXMP` plus equipment `ITEM_MODIFYMP` (`CHAR_WORKMAXMP`); nothing else raises it (no level or stat term) | `char/char.c:2911`, `item/item.c:1401` | 100; no item here modifies it |
| No natural regeneration: nothing restores `CHAR_MP` on walking, on a timer, on a level-up or at the end of a battle | every `CHAR_setInt(…, CHAR_MP, …)` in the tree (magic, healers, GM commands, item_event, battle status effects) | none |
| The healer NPC restores 耐久力 and 气力 | `npc/npc_healer.c:109` `NPC_HealerAllHeal`; the paid window healer `npc/npc_windowhealer.c:499` (HP, MP or both, priced by level) | 休息 / 恢复体力 at the Samgir villager (`GameSession.heal`), free as before |
| A defeat sets 耐久力 (to 1 in the original) and leaves 气力 alone | `battle/battle.c:1156` | a defeat's recovery keeps 气力 |
| The status window's fifth row is 气力 | `system/menu.cpp:11676` (`pc.mp`) | status window, the field HUD line, the battle hover (`system/mouse.cpp:690`: only the player's own line shows 气力), the party 快速战斗 line, the GM summary |

The battle "@" command adds 30 气力 (`battle/battle_command.c:424`), but no client sends it; `BATTLE_MpDown` (`battle/battle_command.c:20`) charges pet skills only in PvP. Neither is built.

Save: `SAVE_VERSION` 4 adds `player.mp` and `equipment`; a version 3 save loads with 气力 full and nothing worn.

## A 精灵 is an equipment item's spell

There is no 精灵 item of its own. An equipment row of `data/itemset.txt` names a spell (`magicid`, column 56) and what casting it costs (`magicusemp`, column 58; `item/item.c:83-85,361-363`); the spell is a row of `data/magic.txt` (`magic/magic_base.c` `MAGIC_initMagic`: name, comment, function, `MAGIC_OPTION`, then `MAGIC_ID`, `MAGIC_FIELD`, `MAGIC_TARGET`, `MAGIC_TARGET_DEADFLG`; `include/magic_base.h`). The battle 精灵 menu lists the magic of the five equipment slots (`system/battlemenu.cpp:660-1140`: `magic[i]` for i 0..4 is `pc.item[i]`), and the server takes the slot number (`battle/battle_command.c:333` `J|slot|target`, slot below `CHAR_EQUIPPLACENUM`).

The healing spells (`data/magic.txt`):

| Spell | Function | Option (power) | Field | Target |
| --- | --- | --- | --- | --- |
| 治愈的精灵 Lv1..6 (id 0..5) | `MAGIC_Recovery` | 80, 160, 320, 480, 800, 1160 | 0 all | 0 MYSELF |
| 滋润的精灵 Lv1..6 (10..15) | `MAGIC_OtherRecovery` | 65, 130, 260, 390, 650, 880 | 0 all | 1 OTHER |
| 恩惠的精灵 Lv1..6 (20..25) | `MAGIC_Recovery` | 50, 100, 200, 300, 500, 600 | 1 battle | 8 WHOLEOTHERSIDE |
| 复活精灵 Lv1..4 (50..53) | `MAGIC_Ressurect` | 100, 300, 500, 700 | 1 battle | 1 OTHER + dead |
| 镜子的精灵 (260) | `MAGIC_MagicDef` | 反 turn 1 | 1 battle | 1 OTHER |

The equipment built here (the cheapest Lv1 carrier of each; `itemset.txt` rows):

| Key | Item | Slot | Level | Stats | Spell | 气力 | Cost | The pinned server sells it |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `haru_armor` | 1011 哈鲁Lv1铠2 (graphic 21027) | body (`ITEM_ARMOUR`) | 10 | 防 +6 敏 -2 | 治愈 Lv1 | 5 | 400 | 萨姆吉尔的防具店, floor 1001 NPC (17,15) (`npc/genout/shop_m.create`, `ss_1001_17_15`) |
| `freya_robe` | 1112 芙雷雅Lv1服2 (21009) | body | 10 | 防 +3 | 滋润 Lv1 | 8 | 484 | 卡鲁它那的防具店, 4001 (18,17) (`ss_4001_18_17`); 芙雷雅Lv1铠2 at 玛丽娜丝的防具店 2001 (18,18) |
| `teo_robe` | 1113 提欧Lv1服2 (21009) | body | 10 | 防 +3 | 恩惠 Lv1 | 20 | 528 | 萨姆吉尔的防具店, 1001 (17,15) |
| `koyala_charm` | 1450 柯雅拉Lv1护身符 (22017) | amulet (`ITEM_AMULET`) | 0 | 魅 +3 | 复活 Lv1 | 20 | 1000 | no shop or drop in the pinned data; Lv2 (1451, 复活 Lv2, 35 气力) is sold at floor 10920 (47,51), Lv3 (1452) by 道场的商人 at 1008 (28,18) |
| `mirror_charm` | 1460 美丽尼亚护身符1 (22018) | amulet | 10 | 魅 +1 | 镜子 | 5 | 4800 | not sold |

Many other items carry these spells (合成 armour, higher 哈鲁/芙雷雅/提欧 tiers, weapons such as 山贼的小棍棒); only the rows above are built.

Where they come from here: none of those shops exists in this world (map 1001 is there, its 防具店 keeper is not; 4001, 2001, 10920 and 1008 have no shop NPC). They are therefore sold at the Samgir item shop (1002) at their `itemset.txt` cost, a convenience like the mirror, and granted by GM 调试 「发放精灵装备」 (one of each and full 气力). Selling pays half, as every item in that shop does here (the original's `sell_rate` is 0.2).

Equipping (`char/char_item.c:330-391`): an item whose `ITEM_LEVEL` is above the player's level is refused with 能力不足无法装备。 (`LACKOFCLASS`), and two items of one type in the two decoration slots are refused with 无法同时装备两项同种类的物品。 (`CANNOTEQUIP2`); both amulets here are `ITEM_AMULET`, so 柯雅拉 and the mirror are never worn together. The mirror keeps its old equipping (no level check), as before. Charm modifiers are not applied (as for the mirror).

## Casting

`magic/magic.c:26` `MAGIC_Use` (field, `lssproto_MU_recv`, `callfromcli.c:1282`) and `:79` `MAGIC_DirectUse` (battle, `BATTLE_COM_JYUJYUTU`, `battle/battle.c:6772`) read the item's `magicusemp` and call the spell's function, which checks `CHAR_MP < mp` first (then returns FALSE: nothing happens, nothing is spent), subtracts the 气力, then heals (`magic/magic.c:132,156,304,324`). A 家族 member of 光精 or 暗精 pays 70 % for some spells (`MP_RATE`, `magic.c:22-58`); there are no families here.

Too little 气力: the original has no message. The client draws the entry red and plays the refusal sound 220 when it is chosen (`battlemenu.cpp:755,1131`; the field menu `menu.cpp:17295`). Here the battle menu does the same, and a command that still arrives is refused with 气力不足。 (ours).

### In battle

`battle/battle_magic.c`, with `_MAGIC_REHPAI` defined in the pinned `include/version.h:137`:

- `MAGIC_Recovery_Battle` (`:519`): MYSELF only on the caster, OTHER only a single target (toNo below 20). Effect on the caster `MAGIC_EFFECT_USER` 100600; on the healed `SPR_heal` 100601 for power ≤ 100, `SPR_heal2` 100602 ≤ 300, else `SPR_heal3` 100603.
- `BATTLE_MultiRecovery` (`:282`), per target: `UpPoint = RAND((power*0.9),(power*1.1))` (`include/util.h:79` `RAND(x,y) = ((x-1)+1+(int)((double)(y-(x-1))*rand()/(RAND_MAX+1.0)))`, truncated to int). `_MAGIC_REHPAI` skips `GetRecoveryRate` (the vitality bonus) and the percent form. A rider shares it with its mount by what each is missing: `Magic_RideGetHP` (`:500`) `share = (rider_missing*100)/(rider_missing+mount_missing)` (at least 1 in the divisor), rider `UpPoint*share/100`, the mount the rest. Each is capped at its max.
- `BATTLE_MultiList` (`battle/battle.c:219`): a single target that is down or gone is replaced by a random standing member of that side; 20/21 (`TARGET_SIDE_0/1`) are every standing member of that side, players and pets. The original client lets 恩惠 pick either side; ours offers the caster's own.
- `MAGIC_Ressurect_Battle` (`:2753`) and `BATTLE_MultiRessurect` (`:1563`): `BATTLE_MultiListDead` (`battle/battle.c:514`) keeps the target only if it is down; then `RAND((power*0.9),(power*1.1))`, at least 1, capped at max; no mount share. Effects `SPR_fukkatu1..3` 100607-100609 (≤ 100, ≤ 300, more). On a standing target nothing happens but the 气力 is spent. PvP never revives players (no PvP here).
- The spell takes the player's action for the turn; it is resolved in speed order like an attack. A pet revived this turn acts from the next one.

Loyalty side effects are not built: a pet healed once per battle gets `AI_FIX_PETRECOVERY`, a revived one `AI_FIX_PETRESSURECT` (`battle_magic.c:491,1668`); `_TYPE_TOXICATION` (poisoned members cannot be healed) has no poison to act on.

### Outside battle

`magic/magic_field.c:20,82`: `power = RAND((power*0.9),(power*1.1))` in float, added as `(int)power`, capped; no mount share and no vitality bonus (`_MAGIC_REHPAI`). Messages 耐久力回复N, X的耐久力回复N and, to the other player, 藉由X耐久力回复N. Only `MAGIC_FIELD` 0 spells (治愈, 滋润); the client's field 精灵 menu offers MYSELF and OTHER (`menu.cpp:17295-17340`; the all-side cases are `#if 0`). Targets (`callfromcli.c:38`): 0 the player, 1..5 its pets, 6..10 party members. Here: the item window's 精灵→自己 and, for 滋润, →出战宠; any carried pet by the `use_spirit` command. Party members out of battle are not built.

## Battle command and screens

`battle_command` `action` `spirit:<slot>` (`body`, `amulet`), `target` a code of the caster's own screen: 0 itself, 1 its pet, 2+2i ally i, 3+2i ally i's pet, 20 its side. In a party battle each member's code is mapped to the canonical battle (`PartyBattleSession._target_ref`), and the frame's `spirit` (caster, target, heals) is mapped back to each viewer's screen (`_view_ref`): a member heals the leader with code 2 and sees itself as the caster, the leader sees ally 0 heal it. The battle view shows `MAGIC_EFFECT_USER` on the caster and the heal or revive effect on each healed actor (original art from `tools/import_mirror.py`; without it the HP bar and heal number still show). 镜子的精灵 now costs its 5 气力 (`MAGIC_MagicDef`); it stays refused in party battles.

## Automation (用精灵补血)

Ours, not the original's: `training.spirit` (on by default; 轻松助手 「用精灵补血」). 自动练级, solo or a party leader's, casts a worn healing 精灵 before anything else when the player, its mount or its pet is at the 停机线 (治愈 on itself, else 滋润 or 恩惠; the mount through the rider's share; 复活精灵 on its fallen pet), and in a party battle also on a teammate at the line (滋润 on the lowest, 恩惠 when two or more are) or a fallen one (复活精灵). Without the 气力 it falls back to what it did before: a party battle drinks 回复药, a solo run stops (saying 气力不足以用精灵). Between troops it casts the field spells (治愈, 滋润) on the player and its battle pet or mount until above the line. A member's 组队自动战斗 preset (`party_auto`: `{hp, spirit}`) plays the same choices, and the party guard casts each player's own field 精灵 before their 回复药. The 恢复护符 keeps healing pets at half HP as before.

**全体补血** (`training.side_heal`, 0 to 100, default 50, 0 off; the 自动练级 window's 「全体补血：有人体力低于 %」): before the stop-line choices, a worn 恩惠 heals the whole side as soon as anyone standing on it is below that percent of their HP (exactly at it does not count): the caster, its battle pet and mount, and in a party battle every teammate not escaped, their pets and mounts (fallen ones do not count; 恩惠 does not revive). It needs 用精灵补血 on, and the 气力 when 精灵不耗气力 is off. Without 恩惠 worn nothing changes (滋润, 治愈, 复活 and 回复药 at the stop line). In a party one 恩惠 a turn is enough: the leader's run commands first, then the automatic members in slot order, and an automatic member skips 恩惠 when an earlier command that turn already casts one (`PartyBattleSession._side_heal_taken`; a member commanding by hand is not changed). Members use their own threshold (`party_auto` `{hp, spirit, side}`), set in their own 自动练级 window.

## Not built

Attack and status 精灵 (猛毒, 硬化, 混乱, 酒, 睡眠 and their all-side forms, 大地/水/火炎/疾风/调和, 彩虹/极光, 光, 守护, 复活光/镜/守护, the `_ATTACK_MAGIC` spells), status recovery (净化), pets casting 精灵 (pet skills), family 气力 discounts, the paid window healer, party members as field targets, and 精灵 on items other than the five above.

## 精灵不耗气力 (not the original)

A per-character rule, **on by default**, in 设置 → 规则 (`set_free_spirits`, saved as `free_spirits` in the profile; a save without the key counts as on). Some private servers made 精灵 free; with it on every worn 精灵 and the 镜子的精灵 cost 0 气力 (`GameSession.spirits()` reports `mp` 0 and battle configs carry `mirror_mp` 0), in battle, outside it and in automation. 气力 itself is unchanged and still shown. Turned off, the original costs above apply.
