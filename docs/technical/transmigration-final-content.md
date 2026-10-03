# Transmigration final cave content

The first source handoff pins original data without registering or enabling a
production module. `tools/transmigration_final_quest_sources.json` currently has
no active create/scripts; its reviewed bindings and staged maps are evidence.
`client/tests/fixtures/transmigration-final-identities.json` was read directly
from original create blocks, independently of the runtime catalog/importer.
The source revision is `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.

## Identity contract

All IDs follow the existing `script@map:x:y` convention. Four original WarpMan
actors, five changeevent archaeologists, two NPCEnemy actors and the king make
12 distinct identities. Nurses are excluded.

| Script | Map/cell | Original create ordinal | Role |
| --- | --- | --- | --- |
| genout/wpm_300_103_228 | 300 (103,228) | genout/sikkoku.create 83 | Same-map outer gate to (105,228); not a cave root |
| genout/wpm_300_108_225 | 300 (108,225) | genout/sikkoku.create 84 | Cave root to 32001 (29,3) |
| genout/wpm_32016_31_39 | 32016 (31,39) | genout/sikkoku.create 86 | Same-map gate to (31,37) |
| genout/wpm_32021_31_51 | 32021 (31,51) | genout/sikkoku.create 87 | Final gate to (32,47) |
| giiru/event/sikkoku01 | 32002 (4,23) | giiru/event/sikkoku/sikkoku.create 0 | Original branches 0,1; item 2771 |
| giiru/event/sikkoku02 | 32006 (46,46) | same create 1 | Original branches 0,1; item 2772 |
| giiru/event/sikkoku03 | 32009 (49,20) | same create 2 | Original branches 0,1; item 2773 |
| giiru/event/sikkoku04 | 32014 (14,48) | same create 3 | Original branches 0,1; item 2774 |
| giiru/event/sikkoku05 | 32016 (31,43) | same create 4 | Only original explanation branches 1–7 |
| 777/ten.arg | 32021 (31,28) | same create 5 | npc_transmigration; graphic 100444, facing 4 |
| 300/sb_skr.arg | 32010 (54,30) | 300/sb_sikkoku.create 0 | Five enemies; victory Warp 32011 (56,36) |
| 300/sb_skt.arg | 32020 (20,9) | 300/sb_sikkoku.create 1 | Ten enemies; victory Warp 32021 (29,57) |

The king's full ID is `777/ten.arg@32021:31:28`. The integration v1 contract uses
`service="transmigration"`, `script="777/ten.arg"`; these are service dispatch
fields, not a new player-save shape. Activation events await integration-owner
confirmation. END48–52 are original rebirth history flags and must not become
additional cave-entry conditions. Existing shared parser/merge hooks need an
explicitly reviewed service extension; this source-only commit does not alter
them or invent a parallel schema.

All four gates require LV>79 and END39/40/42/46, with MONEY:-1. The outer same-map
gate does not itself establish cave arrival. Archaeologist MESSAGE actions can
grant items and need the same authoritative arrival/save checks as ACCEPT.
The four history orbs are explanatory items, not additional king requirements.
Their original item fields 78–81 are 1/1/1/0; logout handling belongs to I.

END53 original branch 0 remains excluded by explicit project decision. It is
not replaced with invented rewards or consumption. PETTRANS, sixth/seventh
rebirth, nurses and special Boss skills remain unavailable. The complete Boss
enemy order is frozen; original special tactics remain metadata and must not
be presented as restored AI. No settlement or arrival implementation is in
this handoff.

## Verification

Run `.tools/asset-venv/bin/python -m unittest discover -s tools -p
 test_transmigration_final_sources.py -v` (one shell line). Five tests cover
exact create fields/ordinals, source and 21-map SHA, changed binding/map/source
rejection, four gate conditions, five/ten-enemy order and victory destinations,
original selected/excluded branch numbers, and source-only production closure.
This proves source identities, not a completed natural route. Route geometry,
real transactions and final public union remain subsequent content work.
