# Quest helper chain status audit

The helper projects player-facing chains; the original journal and original flags
remain unchanged. Status is not inferred from unchecked rows or `current`: first
requests are current before acceptance, optional rows remain unchecked, and legal
navigation can suppress current rows without ending a task.

| Chain | Source semantics and projection |
| --- | --- |
| Wood 18/19 | Hahn's water/axe exchange sets END19 and clears NOW19. Barl's axe delivery sets END18, clears NOW18, and gives recommendation 2467 plus broken axe 2484. Merchant trades recommendation for permit 2478; harvest produces wood 2468; settlement consumes permit and wood, including the legal zero-wood payout. END18 therefore precedes mandatory follow-up. Any outstanding 2467/2478/2468 keeps the helper active. Broken axe 2484 and optional repaired axe 2485 alone do not. CLEAN18 eligibility remains the actual source branch and does not activate a fresh run. |
| Adult 4 | Request sets NOW4, delivery sets END4. Existing projection is sufficient; uncollected/unchecked rows do not override completion. |
| Munde 9–12 | NOW9 spans village requests and stone deliveries; END10/11/12 do not end the main task. Final village reward sets END9. Existing projection is sufficient. |
| Jan 20–22 | END20 closes meeting Jan, not the separate letter quest21. Sala's request sets NOW21; Jan's equipment branch tests END20 + NOW21 and sets END22, never NOW22. Project quest22 active between these source transitions. END22 remains completed while NOW21 continues until letter delivery. Merely meeting Jan does not start quest22. |
| Dream 32–34 | Elder REQUEST sets the exact round's NOW flag and supplies light2603; reward sets that round's END. Shared light or unfinished battle alternatives must not activate future rounds or reopen past ones. Existing projection is sufficient. Optional time hints do not count as active work. |
| Dojo44 | Existing golden helper already projects tickets, challenge floors and reward room as active without NOW44; END44 records final pet exchange. Preserve that helper's status. |

Evidence: `references/chenmingbiao-stone-age/gmsv/data/npc/jaruga/event/20501ev1`
through `20501ev5`, `jaruga/event/event20_4`, `event20_6`,
`seimu/event/event01_1`, and their imported canonical branches.
`quest_helper_status_test.gd` executes the wood source transactions through
zero-wood settlement and CLEAN18, then checks active/completed/unstarted boundaries
for the neighbouring chains. These fixture positions isolate exchange semantics;
they do not certify route traversal. No server mutation or original flag rule changed.
