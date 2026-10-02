# Scenic-map exclusions superseded by reviewed bonus quest modules

The full run and its low-load rerun found three obsolete test exclusions. The
production importer output agrees with the newly registered source manifests;
no runtime/importer behavior change is needed. Existing exclusions for other
unreviewed maps remain asserted.

## Jyaruga scenery:20608

`client/data/quest-modules.json` registers `jan-cave`. Its
`tools/jan_cave_quest_sources.json:world.map_sources` pins original
`gmsv/data/map/jyaruga/dungeon/dan_2-06-08` (SHA256
3674dd560c13dc25afad82acaaaaac75e561d4264a941465d05136174a358d1c).
The active MapWarpPoint table has 20607(75,13)→20608(0,7) at line2308, before the
alternative (0,8) at2310. Return rows2309/2311 both remain. The prior audit's
active-loader/event first-match evidence is in `bonus-cave-chains-audit.md`.
`jyaruga_scenery_test` now checks the imported map path/field classification,
that exact selected entrance and both return targets, instead of excluding it.
20711/20712/20001/21103 remain excluded.

## Jyaruga interiors:851

This is Golden Bui's advanced entrance hall, not a Jan side effect. The registry
uses the explicit `golden-bui` builder. `import_golden_bui.build_sidecar` exports
its reviewed `map_sources` into the module world fragment, consumed by
`module_world_reviews` and `import_world`'s local `quest_maps` set. The source is
`gmsv/data/map/quiz/quiz00b` (SHA256
9a0a1d75437018fbf0f6cd11a46b8da8ce0de0ba685010de35b90218e97f0682).
The active mapwarp line1266 connects4020(12,9)→851(28,29);1268 connects
4020(11,9)→851(30,29), preceding duplicate1270→851(29,29).
The matching `quiz.create` entries are at1531/1549, with original returns at
1540/1558/1576. The source audit is `golden-bui-route-audit.md`.
The test now loads851 as reviewed, checks the first-match arrival, exercises
both real entrance/return pairs and the remaining return at(29,29). It retains
all other deferred maps and original interior walking/arrival-suppression checks.

## Seimu dream maps and clock

The reported failure is specifically the old assertion that42(45,59) is absent.
`dream-cave` now declares `portal_choices` selecting the active MapWarpPoint
line2803→42(31,44), before duplicate2835→42(36,44). The test asserts and traverses
that exact source destination, instead of assuming the ambiguity is unresolved.
Neither destination crosses the final guards.

The same test also explicitly checks all five reviewed entrance records, their
source lines2746/2748/2749/2751/2801, phase suffix and original41/42(11,8) target.
It invokes the actual game arrival path at server-controlled phase boundaries:
A open300/closed301, each M open930/closed931, N open700/closed701. Closed arrival
stays outside with the server refusal; open arrival reaches the original map and
cell. The injected server clock is restored afterwards. Other village portals,
unreviewed6012, developer-only400 and normal arrival suppression remain covered.
This is headless control-path coverage, not a new rendered-pixel claim.

## Verification

Four targeted suites passed with two jobs in59s (no script errors):
`/private/tmp/foundation-four-regressions.log`, with individual logs in
`/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-hq_tuh4k`.
The area test's unrelated shared clock was then made deterministic and that
suite rerun separately (`/private/tmp/foundation-area-final.log`). No full run.
