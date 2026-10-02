# Late bonus reward equipment and old metadata instances

Item 2487, 母亲的发饰, is source type 13 (`gmsv/include/item.h:25`,
ITEM_EARRING), not a helmet despite its displayed name. `gmsv/item/item.c:1242–1245`
places it in CHAR_DECORATION1, matching the existing project `amulet` slot.
`gmsv/data/itemset.txt:2070` has level 0 (column22), durability 200000
(columns30/31), and fixed charm +2 (columns49/50). All other ordinary stats and
magic/resistance columns are zero/empty. The definition enables only these
existing ordinary attributes. It does not add a slot or a magic runtime.
The source table SHA and full columns are retained in the effects fixture.

2460/2505 were defined by the dragon route owner. Their old metadata-only unworn
instances, like 2487, can have zero durability in existing saves. Add only these
reviewed IDs to the existing NEWLY_WEARABLE migration: initialize the original
maximum while preserving UID/item fields, without changing save version. Positive
existing durability remains unchanged. Equipped zero-durability records must be
rejected, not repaired. Normal wear removes a broken finite-durability item, so
this migration does not resurrect an ordinarily broken instance.

The new rejection test revealed a pre-existing JSON number-type problem in
`OriginalEquipment.worn`: an integer UID searched through raw JSON float values
with `in` did not identify the equipped instance before normalization. The shared
predicate now validates an integral numeric value then compares normalized ints;
this preserves strict save validation before migration and works equally in the
ITEM backpack predicate. Nonintegral/non-numeric slot values remain invalid.

2605/2606 definitions remain with the dream route owner; their migration is not
added ahead of their committed definitions. BODY/other missing slots remain
metadata-only. The equipment schema, instance keys and normal wear are unchanged.

Validation: source effects fixture is reproduced from the pinned table; the
actual Session save/load tests verify fixed modifiers, source slot/type/level,
unworn old zero migration, worn zero rejection and positive-damage preservation.
The effects, dragon equipment, wood equipment and ITEM predicate suites pass.
