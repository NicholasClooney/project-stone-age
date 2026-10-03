# Transmigration confirmation UI

The confirmation uses only `world.session.snapshot()` and the existing link
callback protocol. It never accesses a backend or submits computed stats,
rewards, random seeds, arrival proofs or transaction grants. Only the exact king
`777/ten.arg@32021:31:28` can enter it through a top-level `transmigration` reply.

The authority's sacrifice UIDs are the initial selection. Inline buttons show
full names, levels and UIDs for carried pets of each requested template in their
existing order; pet storage and other templates are excluded. Changing selection
requires a new authority preview. Confirm sends only its token. A rejected save
leaves that token available for retry; profile updates disable confirmation and
offer a fresh preview. A server rejection always remains visible. The UI does
not claim that every rejection is retryable: token validity stays server-owned.

Closing before confirmation cancels that exact token. After confirmation has
been submitted, the window explicitly says that closing cannot retract it.
Pending preview callbacks outlive destroyed windows through weak guards.
Abandoned-token cleanup waits until all preview replies on the same link have
arrived; a token reused by a newer live window is protected in either reply
order. Disconnection, movement, switching NPCs and world teardown use the
existing dialogue lifetime and the same precise cleanup path.

The scrolling content presents the authority's fixed-point inheritance as
hundredths, new point pool, selected pets, reward template and return location,
plus the frozen flag/asset policy. It does not calculate eligibility or display
unpublished random growth. The fixed bottom actions remain usable at 390×844.

## Validation boundary

`transmigration_confirmation_ui_test.gd` uses explicit synthetic protocol replies
and no backend. It exercises real viewport clicks, same-template UID switching,
busy/stale controls, save-rejection retry state, close/success handling, both
late-reply orders, switching NPCs and freed-world cleanup at desktop and portrait
sizes. Optional `STONE_AGE_PROOF_DIR` captures rendered frames only in a graphical
run; the test positions an unfocusable window offscreen. The existing
`original_quest_services_ui_test.gd` also passes over real localhost WebSocket,
covering the unchanged ordinary dialogue path.

These are UI and protocol-lifetime checks, **not successful natural transmigration
or real save-failure tests**. The foundation service remains closed. Real king
arrival, settlement, two-device invalidation, persistence failure/retry and
reopening after success require the final I/content/arrival commits and a later
integration test. No production service activation is included here.
