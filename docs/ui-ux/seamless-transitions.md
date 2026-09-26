# Seamless dynamic map loading

Keep interiors as separate logical maps. A modern client may stage both scenes together and animate a doorway/camera crossing, but only one map owns the player's authoritative state at a time.

Start with one working hard-coded portal. Then remove the visible loading gap, then generalize. Do not require a whole-world streaming engine.

## Per-portal lifecycle

1. **Idle:** only the current map is active.
2. **Preloading:** approaching the portal requests destination resources asynchronously.
3. **Ready:** resources are loaded; instantiate/stage scene changes on the engine's permitted thread, with collision and interactions inactive.
4. **Requested:** crossing sends a transition request; retain the source and suppress duplicate requests.
5. **Committed:** after server approval, switch logical map/spawn once and activate destination collision/interactions.
6. **Presented:** move camera/player display to the destination anchor; retire the old scene when safe.

Before server integration, a local transition controller performs the same single-commit flow. After integration, the server validates portal, distance, access, and destination; the client never authorizes entry by finishing a preload.

## Edge cases

- Slow load: keep the source visible, pause at the doorway, and show a small loading cue or door animation. A short fade is an optional fallback, not proof of seamless loading.
- Rejected transition: remain at the source and explain the reason.
- Missing/corrupt destination: release staged resources; retain the source; offer retry.
- Rapid approach/retreat: tag requests with a generation ID and discard obsolete results.
- After server commit: if presentation fails, recover from the authoritative destination snapshot; do not locally roll back map membership.
- Re-entry: require leaving the trigger or apply a small explicit cooldown to prevent immediate bounce-back.

Legacy room dimensions may not fit the visible exterior. Use a doorway anchor, camera cut/short blend, occlusion, or expanded presentation space. Logical continuity does not require physically packing every room into the village footprint.

Use a bounded cache: keep current and imminent destination resources pinned; evict least-recently-used unpinned scenes under a measured memory budget. Release old audio/scene references to avoid leaks. Choose preload distances from actual travel/load timings, not arbitrary historical claims.

Acceptance: warm entry and return without black loading screens; cold/failed loads preserve a valid visible state; repeated crossings do not duplicate players/audio or grow memory indefinitely. Classic transition effects use the same transfer logic.
