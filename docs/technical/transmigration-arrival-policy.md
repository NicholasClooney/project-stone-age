# Final cave arrival policy

This project supplement requires server-observed original travel and saved
battles before quest rewards or the king service. It does not add END53, history
orbs, catalog events48–52, or new wild-drop restrictions as player prerequisites.
Production content/service activation remains owned by the integration branch.

## Source and boundaries

Reference revision: `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`.
The exact source NPC fixture comes from content commits `1c0bd94` / `26e7fcb`.
The independent arrival portal oracle contains original mapwarp rows and SHA;
`tools/test_transmigration_arrival_policy.py` compares the complete source set,
including reverse and alternative portals. Source rows remain evidence even
where a destination is not currently supported.

The `transmigration` scope contains32001–32021. All original internal portals
remain eligible routes, including reverse routes; no test driver's chosen path
becomes an exclusive route. The source has no ordinary outdoor portal into this
scope, no ordinary32001–10→32011–20 forward portal, and no ordinary portal from
another map into32021. Original script gates and two saved Boss Warps supply
those transitions.

| Original proof point | Source and result | Private state |
| --- | --- | --- |
| Outer gate | genout/sikkoku.create ordinal83; wpm_300_103_228:1, 300(103,228)→300(105,228) | Entry approach only |
| Cave gate | ordinal84; wpm_300_108_225:1→32001(29,3) | Continuous scope, requires entry approach |
| First Boss | 300/sb_skr.arg:7–9→32011(56,36), original five enemies | `transmigration_first_boss` |
| Middle gate | ordinal86; wpm_32016_31_39:1→32016(31,37) | Requires first stage; no new history-item gate |
| Terminal Boss | 300/sb_skt.arg:8–10→32021(29,57), original ten enemies | `transmigration_final_boss` plus retained first stage |
| Last gate | ordinal87; wpm_32021_31_51:1→32021(32,47) | `transmigration_king` final-room mark |
| King | 777/ten.arg@32021:31:28, source create ordinal5 | Both stages and final mark; private generic action receipt |

Stages are awarded only when the saved private Warp receipt is consumed by the
actual script movement. Merely entering a map, having END flags/items, fighting
a same-template troop, or queuing a Warp does not award them. Stage requirements
apply to all task NPCs in32011–20 and both stages to32021. The two source battles
remain subject to existing single-character fixed-NPC combat restrictions.

## Public entry pocket

The outer gate is not interchangeable with the cave gate even though they share
the original LV>79/END39/40/42/46 conditions. Previously, recognizing only the
second gate as a root would launder a project jump straight to its inner side.
The private approach begins only after the outer gate's saved original Warp.
It follows the full twelve-cell original component between the gates, with
real one-cell collision checks. The entire public map300 is not protected.

Source mapwarp:1889 sends300(104,228) back to300(93,228), ending the approach.
Original return portals:1807 (32001 at29,3) and:1932 (32021 at53,49) return to
300(108,225), exactly on the cave gate NPC. Only a previously legitimate scope
and that actual portal may establish a new approach. It clears prior stages and
allows walking off this reviewed entity landing before reentry. Arbitrary NPC
collision bypasses or project placements cannot use that exception.

## Lifetime and transaction contract

Ordinary same-scope walking and source portals keep stages across rooms. Scope
exit, project movement, reset/load clear them. Leaving the final king component
through an original same-map exit clears its mark while keeping stages; legally
crossing the last gate again issues a new mark generation. Old preview receipts
remain invalid. Original portal landing cells retain the existing one-step
walk-off rule, including the last gate's own portal target.

`action_context` / `check_action_context` / `consume_action_context` are the only
preview API; see quest-arrival-action-context.md. The king uses exact catalog
identity, empty branch and `SERVICE`. Source JSON numeric coordinates are
compared individually; fractional or changed coordinates are rejected. The
owning service must recheck before save, consume only after success, and keep
its receipt/seed/profile-before on save failure. Arrival proofs never enter
profile or client authority.

## Tests and remaining integration

`quest_arrival_transmigration_test` installs the locked original NPCs and an
independent exact portal oracle in an isolated Backend. All interior movement
uses production report commands, both Boss battles are actual source troops,
both failed saves retry, and both stages activate through real close/Warp.
It covers the two public gates, project arrival at the inner gate, original
return onto the NPC cell, cross-floor stage retention, the source middle gate,
two real devices superseding last-gate tokens, actual final-room exit/reentry,
new mark generations, project invalidation and real save/load/new-backend replay
rejection. No scope/epoch/stage/mark is assigned by the test driver.

This is Backend authority integration, not rendered GameScene validation or
completed natural rebirth settlement. Content owner's production world/helper
and I's king settlement must be tested together later. The static portal oracle
includes117 exits, but the basic cave fixture does not add them. After the user's
option B decision, C restored the exact18 endpoints and fire implemented the
fee/guide services. `quest-arrival-prison-lifecycle.md` documents the separate
actual-world lifecycle suite and the lack of a demonstrated natural walking
route into those endpoints under current occupied-NPC movement. Neither this
policy nor those tests modify walls/guardians to invent such a route.
