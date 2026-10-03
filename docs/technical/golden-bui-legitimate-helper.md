# Golden Bui helper: legitimate original routes

This revision adapts task44 helpers and old fixtures to the shared arrival contract. It depends on central dojo policy `b02cd66`, real service NPC context `372481b`, Backend arrival hooks `b2c9ad1` and final original quest transaction hooks `3b5790a`. It does not implement another credential or change source services, question pools, random results, ticket costs or save format.

## Navigation boundary

Protected maps are800–810,820–829,840–850. Public reception maps811/831/851 remain outside the protected scope. The five original script roots are `genout/wpm_811_30_20`, `genout/wpm_831_30_20` (800), `genout/wpm_811_28_20`, `genout/wpm_831_28_20` (820), and `genout/wpm_851_29_20` (840). Source and original portal precedence remain documented in [the source audit](../reverse-engineering/golden-bui-route-audit.md).

Both helper modes resolve canonical server steps. Outside legitimate arrival, protected NPC requests return only the level-band public counter or ticket gate with an empty target NPC ID. The player still clicks the source NPC and pays/presents the original ticket. Inside the route, the current floor, source component, original geometry and two-cell talk distance must all match; the helper retains the current cell. Actual NPC targets additionally pass the shared read-only `check_action`. The final service/original transaction independently repeats its guard.

`GoldenBui.owns` recognizes exact imported event44 source instances, checked against the service catalog. An empty NPC ID is accepted only for the reviewed current-floor coupon point and exact one-cell rectangle (even-floor29,21 / odd-floor18,21). Backend derives that target from `resolve_step`; raw empty IDs and client map/rectangle/NPC overrides confer no authority. Catch-pet51 and generic encounter routing are unchanged. The only public shared edit is the task44 destination dispatch from an event test to `GoldenBui.owns(npc)`.

`walk_destination` is a read-only original collision oracle. The test driver executes the real ticket service, every quiz/janken result and each original portal using production commands. Item collection inputs remain fixtures for transaction/UI matrices; they are not route grants. The full route suite independently obtains coupons from real random battles. Text questions select `submit` by current question type, rather than retaining the previous multiple-choice ID. No additional automatic quest is opened.

## Verification boundaries

- `quest_arrival_dojo_test`: all five source ticket gates, real service save failure/retry, first question and higher-floor no-ticket janken. This dependency test is not presented as a complete top-floor traversal.
- `golden_bui_helper_test`: levels29/30/49/50/69/70, original fees/tickets, all30 project placements, both modes, raw/old-step/forged-coupon negatives, stationary legitimate coupon point, final-room project placement denied, real ten-floor reward and old token.
- `golden_bui_transactions_test`: original entry/reward/warp rollback, unchanged no-ticket janken, UID-independent original source coupons, malformed hands, two real WebSocket devices, replay and reconnect; private answer/state never published.
- `golden_bui_route_test`: three complete original ten-floor routes, natural random coupon battles, saved settlement retries, exact final source pet/coupon/NOW44/END44 and final save rollback. Collision walking uses the central read-only route driver, avoids NPC cells and leaves the original stair landing before encounter walking. Repeated random losses may accumulate spare coupons; the fixture explicitly discards duplicate instances through the existing UID command to preserve the original fifteen-slot bag. Random streams have fixed test seeds; production RNG remains unchanged.
- `golden_bui_helper_remote_test`: a real first quiz precedes GameScene walking through800→801, both sockets receive the new step, same-region movement avoids redundant publications, stale source steps reject.
- `golden_bui_walking_test`: each original band ticket gate and real approach precedes actual remote GameScene walking/field_step/battle. This demonstrates the client encounter path, separately from Backend full routes.
- `golden_bui_ui_test` and `golden_bui_helper_ui_test`: actual remote mouse/key input with true gate/service/portal fixtures. Public helper navigation finishes before the original NPC click. Reward-room setup now traverses all source services; direct protected placement was removed. The helper UI was also rendered silently offscreen at390×844 and all seven screenshots inspected. This is not a claim of full mobile ten-floor GameScene walking or physical keyboard testing.

No imported assets changed, so no importer is required. Existing suite registrations and budgets remain unchanged. Only targeted suites were run; main integration owns the full run.
