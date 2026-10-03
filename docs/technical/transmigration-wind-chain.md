# Wind41→42 source chain

Incremental scope is provisionally 1–1.75 project SP, on completed Samgir=1 and villager conversation=0.5. Reuses the first-stage map/source/ten-enemy/personal-cooldown foundation and quest transactions. Shared UID selection is charged separately once (0.25–0.5 SP); the new cross-quest legitimate-arrival foundation is not charged again here. Validation includes the integrated shared arrival policy and the full-route/mobile acceptance cost. SP does not imply elapsed time.

## Source ownership and behavior

The wind descriptor enables41 and42. Its manifest owns eleven actual NPC instances (one existing shared Munde instance is merged), fifteen original11201–11215 maps,27 required/reward items, two personal180-second guards and the summit ten-enemy Warp. The four `genou` scripts are bound by `sainasu/event/genou/genou.create`; guards by `100/sb_geno.create`; both original gates by `genout/genou.create`. SHA validation, exact create identity and source indices remain required. No32021 or final transmigration settlement is opened.

Will11215(10,10) first requests41; Mu100(346,356) requests42 while41 is active; original Munde11107(24,6) gives2736 andEND41; returning2736 to Will gives2735,Charm1 andEND42. Munde retains original branch0 (stones) before wind branches1–4, so simultaneous quests cannot reorder the original rewards. Lost harp replenishment requiresEND41,END4,NOW42 and no2736 and grants no additionalCharm. Wind41 completion is not42 completion. An ordinary95 pet can select Will's earlier explanatory branch before REQUEST41, exactly as the source; the helper preserves that blocker rather than bypassing it.

`genou_2` preserves all three weighted pools (8/13/14 entries, including repeated IDs) and original first-match priority. The approved high branch lacks a bracelet requirement; middle/low ORs lack END4/42. The explicit UID contract and C evidence are in [wind selection](transmigration-wind-selection.md). `genou_4` supplies2758 when absent, without a synthetic once-only flag. The original return gate deletes only bag2758 using the foundation's ActionDelItem semantics. Original-item shop resale is not added; magic/resistance and unsupported equipment behavior remain metadata as before.

The fixed guards use existing battle AI. Their original tactics and seven skill slots are audited in `docs/reverse-engineering/transmigration-combat-sources.json`; special original boss skills are not restored. `sb_kbu` disappearance is per character after successful settlement and lasts strictly more than180 seconds, matching the approved project replacement for original global NPC state.

## Navigation and legitimate arrival

Wind helper owns only its listed source scripts and the shared `event12`. In11201–11215 both near/arrival require the player's current map and four-connected region, excluding active NPCs and original portal cells. The helper additionally rechecks the current original branch through `check_action`, requires the NPC to be within original interaction reach, and returns only the unchanged standing cell. A real project relocation would invalidate the route; far-away steps remain unavailable. A unique adjacent component resolves an original portal landing; ambiguous landings do not bridge regions. Hidden personal guards alter occupancy/cache identity. Munde delegates to the existing guard-component implementation and cannot enlarge its boundary. Raw NPC, old step and helper routes are reconstructed from server state. Outdoor100 NPCs remain accessible through existing ordinary navigation.

The user's later requirement adds server-side legitimate arrival before task mutations; being in the same component is only an additional navigation condition. The integrated shared policy supplies memory-only evidence through real gates, original portal steps and required victories, with no save-schema changes. Final action checks cover Will REQUEST41/END42, genou_2 rewards, genou_4 bracelet and event12 harp/replenishment, while public Mu remains an ordinary outdoor NPC. No separate wind credential store is introduced.

## Import and verification

From the main repository root, coordinator only, after merging and following the live-save/clean-stop workflow:

```sh
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/palette_images.py
python3 tools/split_manifests.py
python3 tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
.tools/asset-venv/bin/python tools/test_transmigration_wind_chain.py
```

All import work here used pool-c with cloned assets/cache, read-only `.tools`/`references` links, never main/live/saves. Imported art and screenshots are not committed. The isolated wind-only catalogue contains252 quest NPCs and162 items; combined four-chain totals will differ. All27 imported item icons match original pixels and belong to core; all15 map packs exist and retain the8.0 fallback.

`transmigration_wind_chain_test` acquires actual Munde and wind arrivals once each, then reuses that single Backend for all three tiers. Only the independent starting quest flags and carried transaction ingredients are seeded; route/scope/mark state is never seeded. It covers actual source branches, shared Munde ordering, core rollback/reload, each reward tier's rollback/pool/deletion, entrance level/adult checks, raw/old-step navigation and180-second/summit guards. The single end-to-end suite `transmigration_wind_ui_test`, using `tests/support/transmigration_wind_route.gd`, starts once outside the first gate and walks production GameScene original portals throughout first climb, return, outdoor Mu, Munde password/cave/guard, harp, and second climb to42. Original exit lands on the entrance NPC cell; the driver takes a real adjacent movement step off that occupied landing. It runs remotely at390×844 with actual NPC/choice clicks. Its post-completion two carried pets are transaction ingredients, not a claim of natural capture/training. The original encounter catalogue already includes wind cave areas and template95.

The Python route fixture is regenerated from pinned original handlers plus current imported ordinary doors and collision, with solid NPC cells included. It is a planning oracle, not evidence that game movement or rewards were executed. The single Godot end-to-end suite provides that separate evidence. The optional shared selection fixture suite remains independently registered.

## Acceptance evidence

With actual shared arrival modules, Backend hooks and original transaction hooks, the final chain matrix passes in129.253 s. It includes67.569 s route/oracle work,8.086 s battle settlement and3.232 s initial/reload setup; all three offering tiers reuse the same legitimate Backend and take7.761 s together. It retains the default runner budget. The single full E2E passes headless in367.247 s (332.879 s route,13.294 s battle,17.039 s dialogue/click waits,4.035 s startup) and at390×844 with real offscreen rendering in363.958 s. Only `transmigration_wind_ui_test` has an approved480-second exception in both runners; no standalone duplicate route suite is registered.

The12 actual rendered captures under `/private/tmp/wind-chain-policy-shots` were individually inspected: bracelet, summit battle prompt, first Will request, real keyword input, Munde harp, second bracelet and summit, final Will hand-in, original guard appearance, offering source/project note, selected level60 UID and completed helper. The final selected60 is consumed while61 remains. Screenshots are verification artifacts and are not committed.

Final source/asset validation:3 wind import/map/icon tests;3 exact-selection importer tests;96 extracted original-C predicate cases plus the60/61/event/wrong-template deletion candidates; selection transaction and two-device suites pass. The selection matrix explicitly relocates only its isolated transaction fixture to a public map; it does not claim route evidence. The separate natural E2E uses actual source NPCs, maps, doors, guards and server movement throughout.
