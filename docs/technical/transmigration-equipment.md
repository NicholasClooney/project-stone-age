# Fixed ordinary equipment for the four spirits

The shared second-stage equipment change adds exactly 142 source IDs: 138 new reward definitions from earth/fire/water plus carried items2699/2700/2706/2766. Existing1052/1357 stay unchanged. This shared work is counted once, provisionally0.25–0.5 SP on the original Samgir=1 / villager conversation=0.5 calibration; individual chains do not recharge it.

`client/tests/fixtures/transmigration-equipment.json` freezes every ID, source line/raw row, ordinary definition and inactive effect metadata against itemset SHA `c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d`. `tools/test_transmigration_equipment.py` checks that frozen set and the actual runtime table independently against the original source. Source level is zero-based column22, not cost column18. Initial/maximum durability columns30/31 agree for every added item. All four supported ordinary stat pairs are fixed, so no random instance fields are introduced.

The existing ARM, HEAD, BODY, bracelet and amulet slots apply fixed attack/defence/speed/charm. Magic, six resistances, multi-hit, throwing patterns and2699 avoid+2 remain inactive metadata. Imported source prose never silently activates those effects.

132 new positive-durability IDs enter the existing `NEWLY_WEARABLE` compatibility list: an unworn former metadata instance with zero durability receives its source initial durability while preserving UID, order and next UID. Positive damaged durability is never refilled. The ten source-zero IDs2691–2696/2699/2700/2706/2766 are deliberately excluded from that list and remain zero. Existing supported equipment is not repaired. Save schema, item instance shape and five-slot representation are unchanged.

Worn task items still fail original bare `ITEM=` backpack conditions; the existing unequip hint remains visible. No condition is broadened to consume worn items. This does not open a quest, add a shop, restore magic, or implement rebirth settlement.

Directed validation covers all142 definitions/ordinary fields/effect boundaries/level gates, all132 metadata migrations plus source-zero behavior, representative real disk migration/reload, all five slots, core2701/2707/2770, carried-item bag conditions, BODY mutual exclusion and authoritative equip save-failure rollback. Only the independent shared-equipment files belong in this commit; water quest changes are separate.
