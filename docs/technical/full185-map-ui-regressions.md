# Full185 map/UI regression fixtures

Baseline: main `b2836e8`. These changes are confined to the seven assigned test
scripts; no UI product, route policy, gate, save or live-server change is needed.

| Suite | Root cause | Preserved verification |
| --- | --- | --- |
| golden_bui_walking_test | Child redeclared `Route`, now inherited from brothers_golden_ui_test; the script could not parse. | Inherit the same route driver; all three source ticket gates, collision walking, natural encounters and battle settlement still run. |
| dev_map_overview_test | Immediate cell/map assertions predated asynchronous `project_position` and map loading. | Actual mouse event, exact safe landing, modal/input release, full 800×1200 island dimensions and bounded thumbnail; wait for conditions, not elapsed frames. |
| map_labels_test | Same immediate teleport assertion, plus old two-frame map-load delay. | Original names/colors/no-overlap/marker targets retained; use viewport mouse events instead of calling `_gui_input` directly and wait for exact authority destination. |
| original_item_effects_test | Every effects notice was assumed to say `未生效`; bounded random-pool summaries can contain no inactive effects and are not an item-by-item label list. | Static fixtures still check supported equipment stats and explicit inactive magic/resistance. Deterministic rewards retain each inactive effect line; random rewards check exact slot and distinct-item counts, original duplicate-slot weighting, bounded length, inactive-category presence vs no-inactive marker, and metadata export. |
| original_jug_shop_ui_test | Inherited `place_and_click` now invokes dojo-specific routing: public lobby placement `(npc.x,22)` moved the jug shop fixture eleven cells from its y11 NPC. After correcting that, unconditional frame_post_draw hung headless runs. | Keep the existing adjacent public shop fixture, confirm both authority/client `(10,12)`, then real pointer click; wait for scroll geometry. Price1150, UID purchase, quantity, gold, cancellation and portrait bounds remain. No protected arrival is fabricated. |
| original_quest_services_ui_test | Child run never assigned inherited authority; old raw floor801 setup also lacks current route authority. | Use existing golden_bui_route to complete the ticket gate, first-floor challenge and original stair; mirror only the reached location into the remote scene. Source NPC pointer click, ticket consumption, two original questions, final Warp and visible score remain. |
| personal_quest_npcs_ui_test | Child run never assigned inherited authority needed by the brothers route helper. | Initialize host/authority, walk the existing public entrance and original stairs, synchronize the already reached position, then real mouse click. Hidden actor removal, collision restoration, strict expiry, no duplicate residents, relocation and cross-map projection remain. |

The UI suites reuse golden_bui_ui_test's `click_source`, which sends mouse
press/release events through the viewport; service buttons retain hover-tested
clicks. Route drivers issue production commands and establish arrival through
original gates/stairs. Setting the remote display location after a completed
route is synchronization, not a new route grant. The personal-NPC visibility
mutations remain the original projection fixture; this test does not claim to
cover their battle transaction producer.

Only targeted headless suites run for this batch. Headless input/layout evidence
is not a rendered-pixel review, and no screenshots or original assets are committed.
