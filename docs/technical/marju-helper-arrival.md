# Marju helper arrival adaptation

The reviewed arrival policy (`31f2fc1`) uses the saved original `genout/wpm_120_19_15` level50 gate as the root of maps122/118/119. No new mark or event flag is added. The helper routes event37/38 through its own destination function; its single shared dispatch line retains the existing order.

A cave recipient requested outside the maze resolves only to the public map120 gate approach with an empty destination `npc_id`, so arrival travel cannot open the remote recipient. Public map1300 request/return and the map120 entrance retain generic navigation after removing the module's events from the temporary target to avoid recursive dispatch. Inside the maze, both modes return the current cell only after `has_arrival`, current original branch, `check_action`, and actual two-tile NPC range pass. The original maze must be walked; inventory and location do not grant arrival. Step projections refresh at near range and hide unreachable interior actions. Raw NPC and stale step requests are re-derived by the authority.

The original one-way119(103,93)→121(17,15) exit remains one-way. Public1300 END38 reward intentionally does not require a current maze mark after exiting. Mail delivery, MESSAGE stone replacement, and independent ACCEPT stone branches keep their original item/flag rules. Original source files, item definitions, random weapon weights, equipment and production transaction logic are unchanged. Bag branch remains unavailable; source spirit magic remains labelled inactive.

## Targeted checks

`marju_quest_test` retains request/delivery/reward save failures, original full-bag behavior, completion/repeat rules, save reload and two real sockets with stale-token rejection. It now walks the actual maze and its two portals, walks the original exit before returning, checks both helper modes/raw/stale steps, legal independent cutting stone, and project placement/replacement refusal. Independent branch profile fixtures do not grant routes.

`marju_route_test` uses fixed original endpoints and source collision/portal data, not a helper-generated interior destination as its oracle. The source recipient's (97,89) neighbour is walkable; (96,88) is blocked. `marju_ui_test` performs the real gate click, production per-cell maze route and actual exit before public reward at390×844, with real helper/dialogue/equipment clicks. No full suite or live save is used.
