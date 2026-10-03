# Source-map integration regression fixtures

Base: `main b2836e8`. This test-only correction reconciles the complete registered catalogue with older isolated tests. No importer, original map, policy, helper production code, reward or gate condition changes. The main public oracle remains297 NPCs/338 item definitions.

## Earth and original return stairs

`transmigration_earth_route_test` inherited `golden_bui_route_test.fresh`, whose independently isolated Golden fixture now sets enabled events to `[44]`. All Earth NPC lookups therefore returned empty before the real route began. The later “portal to21014 missing” was a cascading assertion at the starting village, not missing map source. Earth overrides only fixture initialization to restore the production registered events, retaining all actual request/material/entry/third-floor gate/fourteen-floor/two-battle/goddess/return/drop steps. Source lookup failure also reports the actual missing script before dereferencing.

`genout/deadroad.create` SHA256 `64020507ce610ca777910683aca755a4ecb388664b9fdb930301d6150f40843d` has the three original21015→21014 returns at create lines232/241/250: `(8,17)→(13,17)`, `(9,17)→(14,17)`, `(10,17)→(15,17)`. All three are present in the imported manifest. The forward21014(14,14) is restored `200/sb_dbt.arg`, SHA256 `c903a1967eb3744cc25734688a47fa7109a1c59c34c2ec581926b3099a4ab357`: victory Warp21015(9,17), exact original ten enemies. It is intentionally not a scenic portal.

`world_region_jyaruga_interiors_test` now asserts the forward shortcut is absent and the original guard's Warp is exact. Its rendering/movement fixture loads the return landing and verifies arrival suppression, walking off, and walking back through the real return door. It does not claim that this placement earns quest authority; the Earth route test separately earns the real saved victory landing. Earth arrival negative tests use authoritative project relocation and assert actual cave position with no route proof, before testing both modes/raw NPC/old step/final transaction. A rejected arbitrary position report would not be a valid replacement for that setup.

## Dana and selected-event public UI

The frozen `dana-public-actors.json` reads original `airway.create`, `shop_m3.create`, `shop_nuke1.create`, `sp.create` bytes independently of the importer. It retains20 original residents/services/decorations, adds the already-reviewed Dana elder `giiru/event/event30_3`, and the fire source instance `giiru/event/sink/sink07@5106:26:15`. Map populations are exactly2/5/6/2/7 for5100/5101/5103/5105/5106,22 total. The fixture stores source SHA values, and the Python test checks both original actors and the exact two quest identities against the static public oracle. The rendered test compares identity/position/graphic/direction/role sets, not only totals.

`original_quest_ui_test` intentionally enables `[1,2,4,15,16,18,19]`. Its exact set is the original13 quest NPCs plus the two original water entrances independently tagged event4 and both Charm services. It keeps exact equality and all original UI interaction checks; it does not enable the whole catalogue or accept a subset.

## Sea passage

`genout/40npc.create` SHA256 `11febc4fd8d83d89b16be32e8276934f5490fe8e5b049a8849424c69cb7aa593`; `genout/dungeon03.create` SHA256 `baf71a27eb74958c37e85ea362e16e0cf515bf31f1a3c5c08ee3ed0c55e267e8`. Original ordinary returns remain31301(10,103)→40(12,1),31401(94,27)→40(1,9),31501(34,2)→40(11,18). The two still-reviewed permit-gated outbound projections are40(1,8)→31401(92,27) and40(12,18)→31501(32,2).

The former sixth convenience portal40(13,1)→31301 is now restored `genout/wpm_40_13_1`, pinned by the water manifest SHA `4080b33fc9c52e705bc93b84a72f36cd8a1e95362386002517ff2f1b28aa326b`. Its source FREE is empty, MONEY300, Warp31301(10,104). A permit does not waive this cost. The test retains all five ordinary-door denial/permit/server/client transitions, compares exact endpoints (normalized integer coordinates), and explicitly checks the paid NPC's299 refusal,300 saved deduction/exact landing, and replay refusal. Ordinary router connectivity is directed: routes into island300 require this paid NPC and cannot be represented as a free permit-only portal. Existing other island directions remain checked.

## Dragon navigation contribution

The global navigation key combines several modules, including registered transmigration helper state. Disabling unrelated events does not imply that key is globally empty. The Dragon test now compares the full key with event17 enabled versus only17 removed, while retaining every other enabled event/helper. Outside Dragon maps, `Dragon.stage_key` must be empty and the two complete keys equal. Real seven-floor route, jade gate, save failures, repeat/restart and two-socket assertions are unchanged.

All seven affected Godot suites and the two Dana source assertions run headlessly and muted. No full run, live save, main asset mutation or reimport is needed. Existing registrations cover the modified tests. The return-door test is functional UI validation, not a new rendered pixel claim.
