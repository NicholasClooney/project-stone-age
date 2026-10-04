# Old three incremental approaches — first run failed six target comparisons

Only quest_auto_public_corridors_legacy_approach_test ran once. UTC2026-10-04T18:13:03.761363–18:13:58.243830; wall **54.482s**, internal53.532s; exit1; **13320 assertions,6 failures**. Process57819 exited, no timeout. Original outer150/condition140 retained. Window immediately released; no other suite/import/full or retry.

All six failures have the identical label at approach_fixture target comparison. Full printed actual selections have exact declared status/NPC/map and integer-valued JSON float coordinates:
- adult jaruga/event/event04_1 /10204/[14.0,6.0], expected[14,6].
- shell sainasu/event/event02_2 /1000/[57.0,124.0], expected[57,124].
- herb jaruga/event/event01_1 /3110/[16.0,15.0], expected[16,15].

Test used raw Array equality against integer literal arrays. Existing core Motion.cell already handles precisely this imported coordinate representation, rejecting non-numeric/boolean/non-finite/fractional/out-of-range values. Test-only narrow correction prepared: use Motion.same_integer for map and Motion.cell for coordinate comparison, retain exact status/NPC/target values; add per-subclause and raw-array equality diagnostic. No raw target/selection/SP/route/production mutation. No rerun yet, so correction is not claimed green.

## Other actual assertions / observations (suite still failed)

All six reached the declared incremental endpoint. Original independent door walk and portal checks, first protection/request transaction, no full quest END, and normal save/load passed. No additional failures were printed.

|case|new audit packets/segments|old audit packets/segments|field calls|protected walk|sim total/public100|wall percase|terminal|
|---|---|---|---:|---:|---|---|---|
|B1|marinas-kou1/1|kou-undersea1/1|41|1|8.6/0.6|3.007s|10201(6,5)|
|B11 SP0|yam-samgir1/1|none|13|0|3.2/0.6|2.876s|1000(55,122), actual2415/NOW2|
|B30|marinas-kou1/1|kou-undersea1/1|41|1|8.6/0.6|3.029s|10201(6,5)|
|C1|marinas-kou447/149|kou-undersea25/9|509|1|55.0/45.1|9.388s|10201(6,5)|
|C11 SP0|yam-samgir698/233|none|710|0|72.7/70.2|11.931s|1000(55,122), actual2415/NOW2|
|C30|marinas-kou447/149|kou-undersea25/9|509|1|55.0/45.1|9.486s|10201(6,5)|

Exact source portals adult/herb:100(470,631)->1100(63,35),100warp.create:313;1100(96,62)->10201(6,4),dungeon00.create:214; then first protected walk6,4->6,5. No10202 permit gate/adult30 gate/full island traversal executed or claimed.
Shell SP0:100(638,491)->1000(50,116),100warp.create:7; actual request at original NPC vicinity55,122 grants2415,END2 remainsfalse. No full shell exchange.

All actual_new_benefit=true, fallback_only=false in this sample, but final old-three acceptance remains NOT GREEN until corrected exact target comparison passes. New IDs have public-v2- prefix; old kou-undersea ID is kou-undersea-outside. No arbitrary starts/full old quest completion/natural combat claim.

## Correction / next window

Only owned test changed to strict existing Motion coordinate normalization and diagnostic subclauses. Same6 cases/start/SP/permit/target/terminal/assertion coverage and outer150/condition140. A future one-run recheck is estimated45–70s based on this measured54.482s; requires parent scheduling, no automatic run. A changed target or fractional coordinate remains failure; no use of int truncation or relaxed distance.

Evidence preserved in this report directory:
- public-expansion-legacy-approach-first.log
- public-expansion-legacy-approach-first-meta.json
- public-expansion-legacy-approach-first-results.json (copied original result, full actual selection also in log)
