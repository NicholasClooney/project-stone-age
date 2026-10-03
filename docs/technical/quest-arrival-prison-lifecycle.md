# Prison arrival lifecycle verification

This is a test/audit increment after the user's prison option B decision. It
changes no movement, walls, NPC collision, fees, save format or arrival policy.
The existing central move hook invalidates a cave scope on project relocation
or scope exit;117 and110 remain outside every quest scope.

## Exact dependencies and assets

- A `0f62cde`, `4443b042`: generic receipts and final-cave stages/entry pocket.
- C `1c0bd94`, `26e7fcb`, `6b8bc2d`: source identities/catalog/reward definitions.
- C `b750a94`, `9b204455`, `f9baa6b5`: prison source audit, world, five services.
- C `f192b8d`: read-only final cave helper and its narrow dispatch.
- UI `c350f879`, fire `47324c72`: prison service UI kind and actual transactions.

The test used a read-only reflink snapshot of C's private imported assets:
452 maps /1717 portals; world manifest SHA256
`3a8c48a515f48ff2c4ed0991783c5fcd81b9fabf2af15ae58755bb498493bb73`.
This is the historical9b snapshot used for this run. C subsequently delivered
final oracle `02d2d8fc` with world SHA
`5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639`;
its fallback/palette resource changes leave the452/1717 geometry and eighteen
endpoints unchanged. This report does not claim the later bytes were rerun.
The test verified the source manifest before and after copying. The worker's assets
symlink points at the independent snapshot, never writes to C/main, and no
importer was run in the shared-assets worktree. Quest NPCs/services are installed
from C's committed source fixture with isolated catalog tags. No portal is
injected: `FinalRoute.install(backend,false)` uses the actual imported world.

## Why the first test failed

The initial test incorrectly assumed every original reward region could walk
back to a prison entrance. All three completed routes were valid, but the
original occupied-NPC/portal geometry yielded no such ordinary walking path.
The initial log is retained as `/private/tmp/quest-arrival-prison-first-failure.log`.
A separate eight-direction traversal with the original corner checks confirmed
this; C independently reviewed the geometry and source C code. Tests were
corrected to distinguish source endpoints from route reachability, without
changing product movement or hiding an actual arrival-policy failure.

| Scope | Source-declared prison endpoints | Ordinary post-reward path under reviewed movement |
| --- | --- | --- |
| Final cave |32020 ten cells; mapwarp779–788 |None found; NPC at20,9 blocks the20,8 frontier. Diagnostic removal reaches only20,8 and is not legal movement. |
| Water |21214 at30,33..39; mapwarp795–801 |None found; NPC at30,40 blocks the30,39 frontier. Diagnostic removal is not a valid route. |
| Earth |21014 at15,4; mapwarp807 |No audited ordinary entry into the upper region. Reward returns land13/14/15,17; mapwarp2447–2454 are upper→lower one-way exits. Row12 is not a solid wall across the whole map, but its other walkable cells do not establish the needed connection. |

`NPC_NPCEnemy_Dying` is a player-victory callback: battle.c3354–3358 and3848–3854,
npc_npcenemy.c416/574. It supplies no player-defeat→prison Warp. The source
no-encounter-equipment conditional in char_walk.c470–518 needs separate review;
this work does not activate an NPC-crossing exception or call the endpoints
proven anti-cheat traps. There is no checked source statement proving intent.

Source revision: `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.
mapwarp SHA256: `b7b50f42efa8e5a3f740d49a8d0c01cbf994d1bb66151b16ff5b5e7c14e7595c`.
The full C follow-up is `/private/tmp/tmux-agents/spirit-earth/prison-entry-geometry-audit.md`;
A's independent traversal/results are in the corresponding quest-legitimate-arrival directory.

## What the suite actually proves

`quest_arrival_prison_test` preserves these separate verification levels:

1. All18 actual world endpoints equal the locked source coordinates and targets.
   No claim of18 independently walkable natural routes is made.
2. Each character completes the real final-cave, water or earth original route
   and actual fixed battles. The final cave also crosses its last original gate.
   The resulting real arrival/mark/action receipt is valid before relocation.
3. The central server **project** position hook moves that qualified character
   into117, clearing its real scope, stages and old receipt. Explicit project
   placement at each of the18 source cells followed by the actual portal command
   works as a negative test: every such move remains unqualified. Placement is
   never called an original-route arrival or used to grant proof.
4. From the actual117 landing, the character walks the imported prison maze to
   the real fee NPC. Failed save rolls back money/location but does not restore
   old cave proof; the same quoted token retries successfully to110. Real walking
   reaches the original guide, whose no-ticket service returns to the recorded
   birth village for free. The persisted return reloads without old proof.
5. A project return to the exact previously qualified reward cell still cannot
   recover its route, stages or mark.

The fixture only supplies preexisting completed-chain flags/materials and
committed source NPCs, never arrival scopes/stages/marks. This suite is Backend
integration, not UI pixel coverage, a newly restored natural death route, or
full rebirth-service verification. Original four-ticket outcomes and fee edge
cases remain covered by the service owner's dedicated suites.
