# Transmigration final cave content

The source handoff pins original data and registers a **disabled** production
module. `tools/transmigration_final_quest_sources.json` imports 12 source-bound
NPCs and five items; the descriptor has `enabled_events=[]` until integration
approval. `client/tests/fixtures/transmigration-final-identities.json` was read
directly from original create blocks, independently of the runtime importer.
The larger `transmigration-final-source.json` is an installable test catalog,
checked against those separate identities and original source values; it is
not the independent public-union oracle. The source revision is
`0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.

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

The king's full ID is `777/ten.arg@32021:31:28`. Frozen service fields are
`kind="original_transmigration"`, `handler="Transmigration"`,
`service_id="777/ten.arg"`, and `branches=[]`. Its `transmigration` payload has
schema1, rules `original-1to5-anson20-v1`, source TENSEI1–5 texts and four original
village reward/return records. These are catalog data, not player-save fields.
Events48–52 are module activation labels, never prior player flags required to
enter. The source handler is additionally bound through `777/allnpc.template`
to functionset `transmigration`; neither `777.old` nor another ten.arg is used.
All four public catalog readers use the same strict identity projection and
return independent deep copies. Empty branches alone never enable a service.

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

## Original ordinary meat drop

Enemy1405 is the fourth terminal-Boss enemy. Original enemy.txt:1037 slot0 is
item2138 with probability100/1000 (10%). itemset.txt:1857 defines 布洛多斯的肉,
type20, cost125, level0, `体125`/`ITEM_useRecovery`. The definition exists; this
is normal original loot, not an END53 reward. Its six-source pile review adds
exactly this one ID: default creation quantity1, original pile flag1, project
stacking still unsupported. Each successful drop consumes one bag slot/UID.
Flags78–82 are0/0/1/1/1, so ordinary storage is allowed.

Meat healing is **not implemented**. Existing recovery code only supports2401;
this item has no active use metadata and its item description states that it
cannot currently heal. No Session recovery path or new economy policy was
introduced. `char/enemy.c:1109–1118` and `battle/battle.c:4705–4729` establish the
creation-time roll and original defeated-enemy transfer. Their SHA are pinned
in the manifest. Original special Boss skills remain metadata.

## Verification and import

Use `.tools/asset-venv/bin/python -m unittest discover -s tools -p
test_transmigration_final_sources.py -v` on one shell line: eight tests cover
exact source identities, map and source SHA mutation rejection, service texts,
normal drop fields/pile sources, and closed descriptor. The shared single-item
source suite covers all34 explicit definitions after this one-ID addition.

`transmigration_final_catalog_test` verifies all four readers, each activation
label, deep-copy isolation and malformed/relocated king rejection.
`transmigration_final_drops_test` runs the actual ten-enemy battle as an
isolated source-loot transaction fixture, checking the100/1000 boundary,
save-failure/retry, duplicate close, full bag and durable storage UID. It does
not claim natural-route admission; that remains arrival-owner coverage.

Private-clone quest/art import command:

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --output client/assets/legacy
```

It produces309 catalog NPCs and339 items: old297/338 plus12 distinct new actors
and only2138 as a new item (2771–2774 already existed in the foundation).
Production activation remains closed. World import/route geometry, helper and
independent final public oracle are subsequent work; settlement/arrival are
owned by their designated modules.

## Complete king reward pets

The reward catalog now includes exactly enemies1377–1381 using the existing
GetPet schema, not just species IDs. Source enemy.txt lines1009–1013 map to
base IDs6/232/244/272/304 at enemybase.txt lines6/206/212/225/236. Level1,
initial stats, growth weights, elements, AI scalar, skill_slots, sprite and size
are retained with both source locations and pinned SHA. This uses the existing
skill-slot representation; it does not introduce a new executable skill list.
Enemy1380's encounter label says 转生诺加洛, while its actual base272 names
洛卡伦恩; the source mapping and base name are preserved without substitution.

| Village | Original first through fifth reward enemy |
| --- | --- |
| samugiru | 1377, 1380, 1379, 1378, 1381 |
| marinasu | 1380, 1379, 1378, 1377, 1381 |
| jaja | 1379, 1378, 1377, 1380, 1381 |
| karutarna | 1378, 1377, 1380, 1379, 1381 |

The independent source test compares the complete five records and all twenty
village/round selections against pinned source lines. The runtime test fixture
and private imported catalog include these records. NPC/item counts remain
309/339 and production events remain disabled. Settlement construction is
owned by I and is unchanged by this content correction.
