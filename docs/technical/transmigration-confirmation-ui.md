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

The synthetic suite is a UI and protocol-lifetime check, **not successful natural
transmigration or a real save-failure test**. The real-service counterpart below
adds those checks using the actual service dependency. The production descriptor
remains disabled; no production service activation is included here.

## Actual service integration increment

`transmigration_confirmation_remote_test.gd` now uses the actual
`transmigration_service_test` route: original outer/cave gates, original portal
oracle, real five/ten-enemy battles with failed-save retries and successful saved
Warps, then the last original gate and continuous approach. Prior END flags and
combat strength remain explicit fixtures, never arrival marks. A real WebSocket
server on port0 serves two clients; the UI client uses actual WS Link,
ClientState, SessionClient and production QuestDialogue/Confirmation, with no
client backend. The surrounding view is a small isolated Control harness;
**it does not instantiate GameScene, render cave/village art, or verify world NPC
hitboxes**. The closed production descriptor is untouched.

Desktop/390 real clicks cover preview, cancellation with identical complete
prestate, exact alternate UID, preview superseded by the second socket and stale
cancel, actual saved preference updates on that socket, disabled old UI, refreshed
preview, actual filesystem save failure, retained token/frozen candidate, successful
retry, exact one-pet consumption, one return location, rejected transaction replay,
remote reconnect and complete disk readback into a new Backend. The real actor
snapshot uses `species=original_N`; candidate display now reads that field rather
than assuming the preview's separate `template_id` also exists on actor snapshots.
`save_failed` is translated to a clear Chinese retry message. Both dedicated suites
are registered; no full run or production activation is included. The separate
GameScene acceptance below records its explicitly authorized private resource
cache import.


## Imported GameScene acceptance

`transmigration_confirmation_game_scene_test.gd` adds the actual production
`main.tscn`, remote-only game and original NPC sprite input at1280×900 and390×844.
It uses C's privately imported product catalog/world (314 NPCs,339 items,452 maps,
1717 portals), not FinalRoute.install or an injected portal/catalog fixture.
The only initial placement is public300(102,228). The existing route driver sends
ordinary authority movement through actual gates/portals, wins and saves both
original battles, crosses the final door and walks near the king. Only that
already reached position is copied into the profile location before the new
remote scene takes its initial snapshot. There is no interior project movement
or synthetic arrival mark. Prior quest END flags and combat strength remain
explicit fixtures; this test does not replay the earlier spirit quest chains.

The GameScene loads the actual king room, renders the original100444 NPC art,
receives real viewport mouse input on the sprite, presents the server preview,
and receives a real hover-checked confirmation click. The actual transaction
returns the scene to1006(15,22), consumes the exact sacrifice once, leaves no
blocking dialogue/input pause, and survives scene teardown and remote reconnect
without replay. Eight rendered images cover king room, confirmation, return and
reconnection in both sizes. Long-route establishment uses the authority movement
driver; it is not a claim of animated client walking through every prior floor.
The separate real-WS suite retains the full multi-device/save-failure matrix.

Resource provenance: C's handoff SHA256 values are
`ef172502a45c447d6777c30abd868ca49c90f5780e1ca4b8aeaca86520a19cb0`
for quests/catalog.json and
`3a8c48a515f48ff2c4ed0991783c5fcd81b9fabf2af15ae58755bb498493bb73`
for world/manifest.json. The consumer verified these before/after an independent
APFS COW copy. The first GameScene run correctly failed because the king PNG had
no Godot .import sidecar in the supplied copy. After explicit coordinator approval,
the consumer verified legacy and .godot were private directories without external
symlinks, then ran **one private Godot headless editor resource import**. It did
not run Python source importers or modify C/main/shared assets. The king .import
and .ctex then existed, and the unchanged texture/click assertions passed.
Generated sidecars/cache and proof images are not committed.

The production activation descriptor is still unchanged and disabled; only test
catalog activation labels are isolated. C's five source-wall portal declarations
remain disabled. Prison transactions and final package full-suite/release remain
with their assigned owners; this test does not enable or claim those outcomes.
