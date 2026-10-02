# Original quest service bridge

This bridge is an explicit extension of OriginalQuests, not a second session or
save authority. The allowed kinds are `golden_bui_quiz`, `golden_bui_janken` and
`golden_bui_gate`. Other kinds are rejected. QuestCatalog exposes them only when
their reviewed event 44 is enabled. This commit does not register/activate 44 or
finish its world/encounter route.

A registry entry may select the fixed builder with
`{"id":"golden-bui","builder":"golden-bui","enabled_events":[44]}`.
`registered_quest_modules(reference, registry)` yields reviewed fragments for
common importer consumers. No arbitrary Python module name is accepted.
Static exchanges still use the manifest loader. `write_quest_catalogs` separates
server sidecars from the public quest catalog before writing either document.

`client/server/original_quest_services.gd` owns an instance of the server RNG and
loads `res://assets/legacy/server/golden-bui.json`. The public catalog contains
only NPC service IDs and source locations. The server sidecar belongs in the
web **core** pack so the local web backend can operate. A public web bundle is
not a secrecy boundary; remote LAN authority never takes answers, question
state, scores, party membership or target coordinates from the client.

GoldenBuiService receives `context.catalog`, `context.rng`, and authoritative
`context.in_party` (the existing ProfileHub party guard). Its pure plan is
applied by OriginalQuests to the latest profile. One token is consumed per
reply; another device opening a dialogue invalidates the previous token.
`quest_choose` accepts only the token, visible choice and optional text input;
extra client fields cannot replace private state. Text is limited to 120 chars.
A party change rejects an ongoing service reply.

Only the reviewed service actions `GetItem`, `DelItem`, `Warp` are accepted.
They use the existing candidate/save/rollback path. Pending answer state is
installed only after an entry ticket transaction saves. Final save failure
publishes neither a result nor movement. A successful final result emits a
`quest_result` event with public text before `position`; the persistent game
message handles that event independently of the soon-to-close map dialogue.
No-ticket janken is the explicitly user-approved original behavior: the bridge
does not add a generic missing-ticket veto. Other economic/progression source
bugs still require escalation under the project source-bug decision.

The common dialogue controller connects the submitted pure service controls to
`world.link.request`. It uses a bounded vertical scroll for question text and
answer controls, preserving the original frame. The old static dialogue path
is unchanged. Full natural-route and mobile rendered acceptance remains the
route agent's task after world/encounter activation.

`original_quest_services_test` exercises Backend/Session and two real sockets,
entry/final save failures, party changes, single-use tokens, forged client
state, and private-field absence in remote dialogue/snapshot. Its fixtures use
three actual create NPC definitions and two original rows from the quiz pool;
this narrow test pool never becomes runtime content. Python checks compare
these fixture rows to the source builder and verify public/private files plus
local-web core pack ownership. Existing Charm, A, original dialogue, and
multi-pet/fee suites were also run as targeted regressions; no full run.

## World and audited drops

Registered fragments may supply `world:{map_sources,restored_scripts,portal_choices}`.
The world importer validates pinned map hashes, selects these maps for ordinary
play, removes scenery shortcuts for restored NPC handlers, and resolves only
explicitly recorded existing portal destinations. Golden Bui retains all 37
reviewed maps, including 831; conflicting 810 exits select the first-created
original route, as recorded in the route audit. An invented destination fails
import. Static manifests may also provide the same optional `world` object.

A module's audited `drops` are exported under public `reviewed_drops` with an
`active` flag derived from registry activation. The encounter catalog caches
these source enemy IDs once at server startup. Enemy creation still rolls the
original enemy.txt slots once; Session validates them against the original
source slots, so forged item IDs or extra copies remain invalid. The existing
1060/A settlement transaction and retained personal party_settlement path now
also cover these reviewed quest-drop enemies, including failed-save close
retry. No global group/group1 source is changed. Restart/reimport is required
after changing module activation.

## Authorized source supplements

Static manifests may include a `supplements` array. Each entry identifies an
original `script` and zero-based `branch`, and requires `annotation` and an
`approval` document path. The importer currently permits exactly two reviewed
Saton additions; this is not a general arbitrary-action override:

- `sainasu/event/event13_1`, branch 0: `end_flags_add:[14]`, only when the source
  action is `EndSetFlg:13`. The resulting transaction sets both 13 and 14.
- `sainasu/event/event13_2`, branch 0: `confirmation_text`, only when source
  `TYPE:CLEAN` and `CleanFlg:13` are unchanged. The existing yes/no token flow
  presents this project-added confirmation; cancel changes nothing and yes
  clears 13 only. User-authorized repeat rewards remain possible; 14 survives.

Branches retain `source_actions`, `source_texts`, and `project_supplement` beside
the effective actions/prompt. Source SHA checks continue to cover the untouched
original file. Unknown flags, branches, scripts and supplement fields fail
closed. See `client/tests/fixtures/original-quest-supplements.json` for the exact
manifest shape and source-bound expected output. This fixture does not register
the cave task or imply that its NPCEnemy handlers are already implemented.

## Original keyword WarpMan subset

`handlers:{"genout/wpm_100_443_127":{"kind":"warpman","events":[9]}}`
selects an actual `npcgen_warpman|file:...` create binding, preserving the same
instance-id scheme. The importer currently accepts exactly the four-field
source subset `WARP`, `FREE:LV>0`, `warp_msg`, `nomal_msg`; other conditions or
actions fail closed. The four Munde/Jan source gates are covered by
`original-keyword-gates.json`. `npcenemy` is not implemented by this slice.

The server emits a presentation-only `kind:original_keyword,input:text`
dialogue and consumes its existing single-use token with `choice:submit,text`.
It compares the original string exactly (no trim/case-fold), rechecks location
and the selected branch, and commits the source Warp via the normal save
transaction. Wrong input returns the original nomal_msg. The text field is a
project UI for the original spoken keyword; the accepted words and destinations
are unchanged. Remote commands cannot supply their own Warp or actions.
