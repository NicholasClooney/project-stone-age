# Complete first-divergence report

## Status and actual run

Authorized same suite with passive observations only, one run. Added ObservedNavigation.plan/local_path wrappers call super exactly once and deep-copy actual return values; did not add calls to the live planner, prewarm it, change its goals or patch product code. ObservedBackend records actual field_step reply after super. Original assertions and real job12 requests unchanged. All A/C/B phases remained in the suite.

External wall25.427s; internal24.377s; exit1;1335 assertions/2 original sequence failures. UTC17:18:18.238888–17:18:43.666443, process36407 exited. Window immediately released. No encounter, chain or additional Godot run. Current UI pilot window respected.

Files in this directory:
- public-expansion-execution-diagnostic.log and -diagnostic-meta.json
- public-expansion-execution-traces.json: full copied diagnostic artifact, preserving original at isolated user://public-corridors-execution-traces.json
- Previous execution-authorized.log and initial logger failure remain unchanged.

Trace schema: modes.A/C/B contain full cells/field_cells, per-move positions (authority/phase/proposal/remaining/plan_count), field_results (command/reply/authority/proposal/remaining/retained_route/plan_count), every actual plan_calls and local_calls (in_plan,map,origin,goal,result). Indices below are zero-based.

## First and only differing logical cell

Position arrays each383 entries (382 field moves including door + original map portal); field_step arrays each382. Exactly ONE corresponding field cell differs; no length mismatch or duplicate-cell evidence.

| index | A authority / field_step | C authority / field_step |
|---:|---|---|
|360|100(611,180)|100(611,180)|
|361|100(612,180)|100(612,180)|
|362|100(613,180)|100(612,181)|
|363|100(613,181)|100(613,181)|
|364|100(613,182)|100(613,182)|

Both call original field_step with encounter=true and get `{ok:true,hit:false,battle:false}`. Random encounter suppression is the explicit compatibility fixture. Actual authority agrees with these calls. This is a real one-cell equal-length alternate turn, not just packet/sample serialization.

## Exact plan provenance — no mid-route replan

Both modes made TWO actual Navigation.plan calls total:
1. plan_calls[0]: map1400(68,90), original village exit. Existing local_path calls[0..2] examined original goals70,116 /71,116 /72,116; both select original exit landing100(259,171).
2. plan_calls[1]: map100(259,171), MATI target1300. Result length383 (after removing initial position, includes door and portal).

Both selected SAME exact source door `100warp.create:403`: from_map100 cell622,190 -> to_map1300 target24,59. No alternate door selection.

A plan_calls[1].result[362] is613,180. C plan_calls[1].result[362] is612,181. Their full initial plan arrays already differ before any public segment executes. For each mode independently, mapping its initial plan except final portal into map/x/y exactly equals its ENTIRE field_cells array. No later planner call or segment consumption altered either sequence.

Actual local_path_calls[3] is the first public search in BOTH modes: map100 origin259,171 goal622,190, result length383 INCLUDING origin. Its result[363] already differs (A613,180/C612,181). Existing plan then examines goals622,191 through622,197 (calls4..10) in both modes.

A local_path count11 total. C count12: extra call[11] has in_plan=false, same public origin/door, is corridor audit recomputation after plan. It agrees with C's selected plan. Crucially, the cross-mode difference exists in call[3] BEFORE C's extra audit call[11]. Therefore the current evidence does NOT support blaming the extra audit search or segment executor for introducing this observed deviation.

## C actual proposal and remaining at first difference

At authority100(610,180), C begins public-v2-yam-mati stride with points:
`611,180 -> 612,180 -> 612,181`.

At field index360 authority611,180: remaining=[612,180;612,181].
At361 authority612,180: remaining=[612,181].
At362 authority612,181: remaining=[]; next retained route begins613,181;613,182;613,183.
At363 new proposal starts from612,181 and points613,181;613,182;613,183.

All record plan_count2. Executor commits exactly its proposal; no first inconsistent executor call is present. A at361 instead retains613,180;613,181;613,182, also from its own plan_calls[1]. There is no actual “A replan at the turn” to report; reporting one would invent a call. We did not add such a query to alter search history.

## World-state equality gap and next cause to discriminate

The fixture uses three independent backend instances and only no_random_encounters=true. This suppresses field encounters, NOT original NPC birth randomness.

Source facts:
- quest_npc_state.gd _init randomizes spawn_rng; spawn_areas selects from source rectangles and versions the per-character state.
- map100 has source-spawn NPC `seimu/event/event02_1@100:230:180:area:525:200`, event35, rectangle[230,180,525,200]. Its region precedes the observed turn, so different open-set search history due to occupancy is possible even though it does not occupy the differing two cells directly.
- C emitted navigation_key contains a stable tail combining version/hash: `2` + `1531214583` + enabled-events hash`3928166476` + false140; B tail uses version2 + override hash739393640 + same enabled hash. C/B world projections are demonstrably not identical.
- A carries no segment proposal/navigation_key; this trace did NOT record A's npc_state.version/records, occupied cells or their hash. Consequently C/B hash mismatch alone cannot prove that A/C occupancy caused the first local_path difference. Cannot certify A/C equivalent starting worlds yet.

No runtime/backend patch justified. Next minimal observation, if needed, is copying actual local_path input occupied cells/hash and npc_state.version/snapshot at entry (without calling refresh), then comparing A/C inputs. No live extra search. If controlled equal-world mode compatibility is approved, the fixture should produce the SAME original spawn state through its normal birth mechanism before any refresh, explicitly isolate NPC birth RNG (not field/battle RNG, not select a winning route), and still assert full fixed A/C sequence; preserve the uncontrolled failure evidence. Do not silently change fixture, enabled events, force door, patch A or accept arbitrary equal-length paths.

## Contract distinction

1. “Each mode executes the actual currently selected A plan” is supported for this observed public leg: entire per-mode field arrays equal that mode's initial A plan, no replan, same source door.
2. “From the same complete starting world, C executes the fixed full A sequence” remains NOT PROVEN; current independent fixtures have unverified A/C world equality, and cross-mode arrays fail. Equal length, endpoint and simulated2x are insufficient. Original equality assertions remain failing.

Scope remains one new representative approach, not full job12 delivery/nine-job benefit. B previously passed boundary evidence remains separate. No core owner action requested on segment executor: observed proposals are consumed correctly. Any future product change must first be supported by exact same-input plan divergence evidence and ownership agreement.
