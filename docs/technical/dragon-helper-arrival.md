# Dragon helper arrival adaptation

The helper preserves the original seventh-floor wall/component check and uses the shared arrival policy from `3f92f72`: a real enabled `200 → 20801` portal, continuous original stairs through `20801–20807`, and the successful saved `genout/wpm_20807_11_37` warp to `(13,35)`. The three original reward branches also require `dragon_gate` through `check_action`. Inventory, position in the room, and a helper request cannot establish that mark.

Both helper modes return only the current position, after checking legitimate arrival, the current original branch, actual NPC proximity and the original seventh-floor component. Faraway players must walk. The three conditional-jade steps retain their source floor, flute requirement and 80% drop explanation, but expose no project teleport target. Outside the cave the helper describes the public entrance. It does not add another entrance, scope or credential. The cache normalizes JSON event numbers before including near eligibility, so walking up to the NPC refreshes the previously hidden action.

Original source transactions and wild drops are unchanged. The spear retains its implemented ordinary ARM modifiers, and the flute retains its implemented charm modifier; the specific dragon body item definitions and source magic remain unavailable. This document does not claim that the generic BODY system is absent.

## Targeted verification

- `dragon_cave_quest_test`: real public portal and seven floors; original flute request; conditional source troops, actual battle victory and jade drops (isolated encounter fixture); gate save failure/retry; all three alternative reward save failures/retries; original item consumption and END17; completed-event duplicate refusal; both helper modes and stale raw/step denial; project placement at the gate cannot restart a route; newly loaded authority does not recover arrival from saved inventory/flags; two real WebSocket clients invalidate stale tokens and cannot duplicate the reward.
- `dragon_cave_equipment_test`: existing source modifiers, slots, UID and save persistence. No shared equipment definitions are changed.
- `dragon_cave_ui_test`: remote client, real original entrance and production per-cell movement, actual helper and dialogue clicks, three-jewel gate, spear reward and equip at 390×844. Three already-collected jewels are an explicit UI inventory fixture; route authority is never inserted.

Dependency-only cherry-picks in the earth worktree are `1825a7e` (pure water source fixtures / generic collision driver), `f3026a2` (shared committed-action mark hook), and `3f92f72` (dragon policy). Conflicts retain only each commit's own new policies and suite, not unrelated six-cave or phoenix context. Main should use its existing equivalent shared commits, not replay those local equivalents. The test registry remains a single `for suite` loop with the existing names preserved.
