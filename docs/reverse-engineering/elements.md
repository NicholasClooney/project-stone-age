# 属性 (地水火风) and 属性相克

Reference: `references/chenmingbiao-stone-age/gmsv/` (GBK source; line numbers below match the files as checked in) and the 8.5 client under `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`. Restoration: `client/server/elements.gd`, tested against vectors from compiling `BATTLE_AttrCalc` verbatim (`client/tests/elements_test.gd`).

## Stored values

Every character has four integers `CHAR_EARTHAT`, `CHAR_WATERAT`, `CHAR_FIREAT`, `CHAR_WINDAT` (`include/char_base.h:312`), 0..100 each, ordered 地 水 火 风. Our data keeps the same order as `elements: [地, 水, 火, 风]`.

| Who | Source | Values |
|---|---|---|
| Player | `char/char.c:111-128`, `:138-141` | Chosen at creation: 10 points, each 0..10, all 10 spent, at most two elements, never 地+火 or 水+风. Stored ×10, so a player always totals 100 and is never 无属性. |
| Enemy | `char/enemy.c:1067` | Copied from the enemybase template (`E_T_EARTHAT`...). Dojo enemies roll a random pair instead (`enemy.c:946-955`); we have none. |
| Pet | `char/pet.c:332` | Copied from the captured enemy. |

The creation screen starts at 0 everywhere with 10 points to spend (`login.cpp:3228-3232`). Its **+** is refused while the opposite element has points; with no points left it takes one from the first other element that has any (`login.cpp:3480-3535`).

Templates in our catalog mostly total 100; 77 total 0 (无属性) and three total 200 or 400. Those are kept as data.

## Battle values

`CHAR_initcharWorkInt` (`char/char.c:2848-2853`) copies the stored values into work values, then, in index order, writes `-value` into the opposite element (`(i+2)%4`: 地↔火, 水↔风) for every positive one. `CHAR_complianceParameter` runs it for players, pets and enemies (`char.c:2953`, `enemy.c:1146`, `pet.c:365`).

`BATTLE_GetAttr` (`battle/battle_event.c:842-900`) turns work values into five battle powers:

- Without `_BATTLE_NEWPOWER`, a mounted player uses `(rider + mount) / 2` per element, C integer division on the work values, negatives included (`:862-880`). The reference build defines `_BATTLE_NEWPOWER` (`include/version.h:96`), which skips the mount.
- Negatives become 0, and 无 = `100 − 地 − 水 − 火 − 风`, clamped at 0 (`:891-899`).

So a player 地100 riding 扬奇洛斯 (水30 火70) fights as 地15 水15 无70 in the classic branch (work values `[100,0,-100,0]` and `[-70,30,70,-30]`).

## Damage modifier

`BATTLE_DamageCalc` (`battle_event.c:1041`) computes the base hit, then applies `BATTLE_AttrAdjust` (`:1117`) before anything else. The critical bonus (`BATTLE_CriDamageCalc`, `:1267`) is added after it, then guard (`:1013`). Counters, pet skills 3/10/50 and the owner-attack path all go through the same `DamageCalc`, so all physical damage is adjusted.

`BATTLE_AttrAdjust` (`:946-1011`) multiplies each attacker power by the damage, then `BATTLE_AttrCalc` (`:795-840`):

```
My_X = Σ over defender Y of  My_X × Vs_Y × AJ(X,Y)     (int × int, then × double; summed as double, truncated to int)
iRet = My_地 + My_水 + My_火 + My_风 + My_无          (int)
return iRet × D_ATTR                                  (D_ATTR = 1.0/(100×100), truncated to int)
```

Constants (`battle_event.c:25-31`): `AJ_SAME 1.0`, `AJ_UP 1.5`, `AJ_DOWN 0.6`, `ATTR_MAX 100`.

| Attacker \ defender | 地 | 水 | 火 | 风 | 无 |
|---|---|---|---|---|---|
| 地 | 1.0 | **1.5** | 1.0 | 0.6 | **1.5** |
| 水 | 0.6 | 1.0 | **1.5** | 1.0 | **1.5** |
| 火 | 1.0 | 0.6 | 1.0 | **1.5** | **1.5** |
| 风 | **1.5** | 1.0 | 0.6 | 1.0 | **1.5** |
| 无 | 0.6 | 0.6 | 0.6 | 0.6 | 1.0 |

地克水, 水克火, 火克风, 风克地. Opposite elements (地/火, 水/风) are neutral to each other. Every element beats 无属性 and 无属性 loses to every element. Mixed elements blend: 地80 水20 attacking 水30 火70 deals `80×(30×1.5+70×1.0) + 20×(30×1.0+70×1.5)` over 10000, 119% (vector in the test).

Rounding: each row truncates once, the sum truncates again, so 1.5× of 999 is 1498 and 0.6× of 123 is 73. The restoration keeps the same operation order in double precision; the test compares 128 results to the compiled C.

After `AttrCalc`, `damage *= At_FieldPow / Df_FieldPow` (`:1008`). Both are `BATTLE_FieldAttAdjust` (`:911-944`): `0.5` on the default field (`BATTLE_ATTR_NONE`, `battle/battle.c:741`), otherwise `0.5 + element × field power × 0.0001 × 0.5`. On the default field the factor is exactly 1, which is the only field we have.

Magic uses its own copy with the same table (`battle/battle_magic.c:19-24`, `:854-881`); we have no attack magic.

## Display in the original client

- Status window: one bar per element in the four slots beside 攻击力..魅力, `value × 0.8` px wide, 8 px tall, at `x+159, y+5` with 20 px rows (`system/menu.cpp:11877-11906`, `PET_WND_ATTR_X/Y` at `:11529`). Pet status window: the same bars on the 攻击力/防御力/敏捷力/忠诚度 rows, 24 px apart (`:15215`). The window art (26073, 26045) already carries the 地属性..风属性 labels and dark tracks.
- Colours: system palette 250 green (地), 254 aqua (水), 249 red (火), 251 yellow (风), drawn filled, with two 1 px offset outlines in 2/6/1/3 (the dark twins) (`systeminc/directdraw.h:10-26`).
- Pet list: one icon per element, big above 50 and small otherwise (`CG_ATR_ICON_*`, 25120-25131, `menu.cpp:12670-12700`). Battle has its own icons 25132-25135.
- Fans and the in-game quiz write values in creation points (`data/question.txt:36`: 石龟 is "地１０").

## Element-changing effects (documented, not implemented)

| Effect | Source | Notes |
|---|---|---|
| 大地/水/火炎/疾风的精灵 | `data/magic.txt:88-107`, `battle/battle_magic.c:2254-2299` | Field attribute for 3-5 turns, power 60-100. Changes the field factor above. |
| 调和的精灵 | `data/magic.txt:108` | Field back to 无. |
| 彩虹的精灵 / 极光的精灵 | `data/magic.txt:109-110`, `battle_magic.c:2143-2148`, `battle/battle.c:2664-2684` | 属性反转: swaps 地↔火 and 水↔风 work values, toggled per cast; re-applied each turn (`battle.c:2740`). |
| Equipment `attrib`/`attribvalue` | `item/item.c:358-359`, `:1445-1486` | Adds to one element and subtracts from the other three, capped at 100. None of our three items (药, 石斧, 镜子的精灵) has it. |
| 旋转属性 items (`_ITEM_PROPERTY`) | `include/version.h:290`, `item/item_event.c:765-810` | Players only: move 10 points around the 地→水→火→风 cycle, forwards or backwards. No such item in the pinned data. |
| Pet skill 攻击转化属性 (`_PSKILL_MDFYATTACK`) | `battle_event.c:963-977`, `battle/pet_skill.c:1514` | Replaces the attacker's powers with one element. Not in the pinned `petskill.txt`. |
| `_BATTLE_PROPERTY`, `_SUIT_TWFWENDUM` | `battle_event.c:979-990`, `:885-890` | Per-character hooks and suit bonuses. Not used here. |

Our 镜子的精灵 accessory is `MAGIC_MagicDef` (`data/magic.txt:112`, reflect one direct attack) and has nothing to do with elements.

## Restoration choices and deviations

- The player starts at 地100 (creation 地10) because character creation is deferred, like the fixed starting stats. The status window's 属性 bars open an editor with the creation screen's rules; unlike the original, the choice stays open after creation.
- Actors saved before this change (and the tutorial species `wooli`, `blue_dragon` ...) take their element from the source template (`CaptureRules.TEMPLATE_IDS`), so no save migration is needed.
- `combat_profile = "classic"` averages rider and mount; `"reference"` follows `_BATTLE_NEWPOWER` and uses the rider alone.
- Only the default field exists, so the field factor is always 1. 属性反转, element spirits, equipment and item changes are not implemented.
- Pet list element icons and battle element icons need unextracted art (25120-25135); the pet list shows none and battle hover shows text ("属性 水30 火70").
- Values are shown in stored points (地80), as the 宠物大全 already did, not in creation points (地8).
