# Original item effects: evidence and runtime boundary

Decision `6ddc77f` and the subsequent batch reward clarification keep equipment
magic/resistance and unsupported use/stat effects as labelled metadata. Actual
ordinary equipment modifiers continue to work. The shared importer and consumer
cover early quests, A rewards and all explicit static modules; no task-specific
effect engine is introduced.

## Data contract

`items[id].effects` contains source-labelled effects:

```json
{"type":"magic","label":"滋润的精灵 Lv3","active":false,
 "raw":{"magicid":"12","magicprob":"100","magicusemp":"16"},
 "source":{"path":"gmsv/data/itemset.txt","line":2210,"columns":[55,56,57]},
 "reason":"原装备魔法运行时尚未实现"}
```

Columns are zero based, and raw values remain strings from the original row.
Magic names/functions/arguments additionally retain `definition.source`, line
and SHA256 of the pinned `gmsv/data/magic.txt`. Column mapping follows
`gmsv/item/item.c:349–363,374–379`: attack37/38, defence39/40, quick41/42,
hp43/44, mp45/46, luck47/48, charm49/50, avoid51/52, magic55–57 and six
resistance pairs63–74. Original use function/argument are columns10/3.

`stats_source` contains the corresponding ordinary stat records, with `stat`,
`label`, raw min/max and source columns. It deliberately makes no static
activation claim: `OriginalItemEffects.resolve(item)` derives each stat's boolean
`active` from the actual `OriginalEquipment.ITEMS` definition and exact fixed
source value. This lets task-owned new definitions (including Marju2688–2690 and
jewel2765) become correctly marked without a second hardcoded support list.
All final effects returned by `resolve` have an explicit boolean `active`.
Here active means runtime support when equipped/used, not current worn state.
Field herb2401 remains active only in `scope:"field"`; no battle use is claimed.

Source-described magic with probability zero is still labelled and preserved;
it is not silently enabled or erased. Original multiple-attack and throwing
weapon behavior receive separate inactive labels when the source requests them.
No spell, status resistance, extra attack or special target selection is applied.

## Ordinary equipment and unsupported rewards

This slice adds only fixed ordinary definitions1357/2489/2491/2492/2493/2494.
Types9/10 use the existing amulet slot (original `ITEM_getEquipPlace`,
item.c:1237–1245), type8 the existing bracelet slot, and weapon types0/2/18
ARM (`:1221–1228`). Numeric modifiers, level and durability come directly from
itemset rows1348,2072,2074–2077. Existing slots and UID records remain unchanged.
A formerly metadata-only **unworn** zero-durability instance of these six ids can
read back and initialize to the source durability; a worn zero-durability
instance is still invalid. The record still has exactly uid/item_id/durability.
No new save field/version, BODY slot or revival system is added.

- 1357 charm+5 is active; its sleep+30 and other negative resistances are not.
- 2482/2483 have original random modifier ranges (including the reversed quick
  endpoints in2482). Current equipment instances cannot retain those rolls;
  their exact ranges are explicitly inactive. No average is substituted.
- 2490 avoidance+3 is inactive; 2493 attack+17 is active but its source triple
  attack is not; 2492 attack+20/defence-5/charm+5 are active but special throwing
  targeting is not. 2494 ordinary attack+7/charm+5 is active, magic inactive.
- 2421 is an ordinary quest object with no invented effect. 1052/2551 BODY
  attributes remain inactive. 2450 retains `ITEM_useRessurect`, argument500,
  labelled “复活至500” inactive. Unsupported A equipment gets per-field metadata,
  not merely a blanket description. Existing supported ordinary stats are never
  labelled inactive.

## Consumers and validation

The inventory adds inactive labels inside the existing bounded scroll stack;
its tooltip retains exact field/source evidence. It preserves the original
item description, durability, equip button and pet refresh behavior. The common
server helper annotates each reward step with `reward_effects:[{item_id,name,
effects}]` and `effects_notice`; it appends the same notice to the existing label
so the current menu already displays the limitation. No helper menu code or
route-specific dispatch/cache lines are replaced.

Source fixtures rebuild all listed fields and known magic IDs. Real Session
checks equip modifiers, exact UIDs, save/readback and old metadata-only instance
migration. Targeted old wood/helmet/battle/remote suites pass. A real390×844
rendered remote inventory proof and clicks verify scrolling/equip/unequip and A
reward effect labels; the fixed inventory frame still uses small text and this
is not a whole mobile inventory redesign. No full suite was run.
