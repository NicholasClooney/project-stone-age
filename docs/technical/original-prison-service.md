# Reviewed prison runtime

`original_prison_service.gd` is a pure planner for the five source-bound prison
actors. The catalog contract is v1.1: `kind=original_prison`, `handler=Prison`,
`service_id=source_script`, empty branches, and an exact five-key `prison`
payload (`role`, `warp`, `condition`, `money`, `del_item`). Original fields and
text remain source evidence. No generic MONEY1 handler is introduced.

The prison fine is a **project change**: quote `min(gold,10)` at talk. A later
balance change does not alter that quote. Zero gold preserves the original
117(225,13) transfer, rather than releasing the player. Paid exit remains
110(23,27). Dialogue replaces the original 90% demand with the fixed project
rule and exact quote.

Each guide checks its corresponding source ticket. The original ticket route
keeps the source destination and entire bare DelItem list. Without that ticket,
free return to the birth village is a **project change**, with no logout and no
item deletion; a different village ticket is preserved. Confirmation binds the
server's selected route, destination and ticket UIDs. Changes require fresh
talk instead of silently switching destinations.

Birth selection uses the first set bit of `original_savepoint_bits & 15`, not
the current map or an `origin` fallback. Missing birth history refuses without
mutation. The C `char_data.c` elders table and `CHAR_getInitElderPosition`
(lines689–720) independently specify 1006(15,22), 2006(20,16), 3006(21,16),
4006(14,20); SHA256
`ec7d3f51982ba9bba9dc3c922c89263c6d3a9733b3188355d3a1280bf9afe990`.
The low-four-bit first-match convention is `NPC_StartpointCheck`,
`npc_transmigration.c:510–520`, SHA256
`d7e40557bc460cc5a094f7e9d143ec4e3094883890a7832393baf713d3995d24`.
These positions are independently checked birth data, not inferred from another
NPC's Warp. Ticket routes still go to 1012/2012/3012/4012(13,13).

The existing quest token and transaction own authority: actual NPC identity,
distance, activity/battle and nonparty conditions are checked before a bounded,
imported target and allowed action plan reaches `transact(..., SERVICE, ..., npc.id)`.
Money, original item UIDs and persistent location share the existing candidate
save; runtime movement is published only after save succeeds. For this service
alone, `services.reply` restores its saved current window after `save_failed`
only if pending is still empty. The exact token and frozen quote can retry;
success/cancel consumes it. There is no await, client retry marker, save schema
change or altered retry policy for GoldenBui or the jug shop.

The source/map owner controls descriptor activation and the 18 reviewed ordinary
entrances. The additional eleven unimported entrances, two unrelated scripted
entrances, other prison residents and chat rooms are outside this service.
Activation is only for the reviewed stage-three integration; an isolated service
UI/transaction test is not a proof of the complete cave route or arrival policy.
