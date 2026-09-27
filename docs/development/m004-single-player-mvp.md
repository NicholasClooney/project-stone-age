# M004 — Single-player MVP

This checkpoint completes the agreed narrow playable loop. It supersedes M003's no-progression/no-save limitations; M003 remains a record of the earlier slice.

## Delivered loop

| Feature | Working scope |
| --- | --- |
| World | Original Samgir, 96×96 Sainas wilderness area, original30×30 item-shop interior and verified portals |
| NPCs | Existing original villager dialogue plus quest/recovery choices; original shopkeeper behind the original counter |
| Original battle menus | Native2×4 panel, original offsets/art, hover/pressed states, target selection, right-click/Esc cancellation, player→pet command phases, original item and pet selection frames |
| Battle | Attack, defend, escape, capture, potion; one enemy, one active pet; speed-based turn order, guard applies at round start; win/capture/escape/defeat; stronger quest encounter |
| Progression | Player XP/levels with allocatable points; pet automatic growth, gold rewards; club improves attack |
| Pets | 乌力100250, 乌力乌力100251, 乌力斯坦100252; up to5 pets; naming, selection, field following, attack/guard, one level2 skill once per battle |
| Items/services | Potion and club with original icons; buy/sell, equip/unequip, use potion; village recovery for player and pets |
| Quest | Accept from villager, win3 ordinary encounters and capture a companion, defeat stronger 乌力斯坦, return for a once-only reward |
| Save/load | One local profile, safe position, stats, inventory/equipment, roster, selected pet/names and quest progress; automatic checkpoints and manual system-menu save |
| Audio | Original village and battle themes, verified Sainas field theme, original UI sounds and verified attack-frame sound |

The quest finale triggers through normal wilderness exploration once eligible. Navigation shortcuts are optional; the actual doorways, merchant, resident and original bottom menus remain usable. Developer zoom/character controls stay separate from original artwork.

## Play guide

1. Talk to the village resident and choose **村外的伙伴 / 休息**. Accept the quest.
2. Use the west exit to explore. Each8 successful wilderness steps triggers an encounter. Select a player action then its target; with a companion, select its action and target too.
3. Weaken an ordinary opponent to60%HP or lower, then capture. While weakening later targets, command your pet to defend to avoid an accidental finishing blow. Bosses cannot be captured.
4. Open the original pet tab to name/select a companion. Win battles together; level2 unlocks its stronger skill. HP persists, so recover at the villager or use potions.
5. Earn gold, enter the original shop at Samgir(67,108), approach the merchant across the counter, buy potions/a club. Use the original item tab to heal or equip.
6. After3 quest wins and a capture, the next wilderness encounter is the stronger opponent. Beat it and return to claim the reward. Reload the app to continue with your saved progress.

Balance tests complete the core loop in7 encounters (currently26 turns with allocated points), including all3 captures. That is a test route, not a measured20–30minute playtime guarantee. Walks, recovery and menu use add time; wider content and pacing remain future iterations.

## Original-flavor evidence and limits

- Battle base25116 and all8 command offsets follow the original `battlemenu.cpp` final panel anchor (player680,65; pet675,48 in800×600). Source references: lines3608–3609,3757–3765,3800–3801,3896; right-click cancellation337–339/3730. Original pet base25140/skill25141, item26061/title26072 and skill-selection26130 are used. Magic/help remain inactive in this scope.
- Status26073, pets26044/26045, equipment26060, inventory26061 and shop26138 are imported and populated against their baked labels. Unimplemented original status fields remain blank/dashes. Slot counts/stacking and automatic growth are deliberately narrower than complete historical behavior.
- Field-window layout follows `menu.cpp`: status `(4,4)` at11307, pets `(4,4)` at12294, inventory `(365,4)` at15887 in640px. `MakeWindowDisp` at1084 anchors right-side windows to extra viewport width. Inventory images26060/26061 share one center anchor: their imported offsets(-136,-220) and(-136,-61) assemble vertically with159px separation into272×440. Field menu tabs toggle closed; Escape remains available. No generic close button is added below these frames. Item use/equip controls and pet detail content remain MVP adaptations.
- Shop fidelity gap: original `directdraw.cpp:3982` maps `CG_ITEMSHOP_WIN` to26138, so the wooden frame is authentic. Original `login.cpp` uses buy/sell/exit entry choices (`shopWindow1`), compact paged rows (`shopWindow2`), and a quantity window (`shopWindow3`). The MVP combines buying/selling, uses larger icon rows, and puts close below the visible shop artwork. These are adaptations, not a restored original shop flow.
- Merchant graphic16033, position(18,15), original greetings and map1002 come from `shop_m.create` and `ss_1002_18_15`. The reachable counter position is(16,15). Portals come from `warp_y.create`; the safe shop entry is one tile inside the original trigger.
- Sainas map marker45 at(633,493) maps through `play_map_bgm` to BGM10, `sabgm_f0.wav`. Shop retains the village track. No unverified victory theme or player-impact sound is invented.
- Full provenance and original file hashes are in locally generated `mvp/manifest.json`, `battle/manifest.json` and map reports. Inputs and derived legacy assets remain ignored, with reproducible importers tracked.

This is one coherent resource-backed MVP, not a certified official release. The2.5 asset pack and8.5 source snapshot differ. Battle formulas/order, capture threshold, regional encounter mix, quest text/reward, prices/stock and recovery are project-defined approximations. Actor status labels and combat messages are adapted; not every historic battle overlay is reconstructed. The short quest uses the original dialogue presentation but is newly authored, not claimed as a recovered original quest.

## Authority and persistence

`client/server/game_session.gd` owns progression/inventory/pets/quest and validates commands. `battle_session.gd` owns turn state and returns copied snapshots. Terminal battle results settle once against a pending battle ID. The client renders accepted results; no server process or network is required. World movement remains the existing local scene controller; future remote movement validation is not claimed complete.

The schema is pinned to `samgir-singleplayer-v1`. Godot stores `user://single-player.json` outside the repository; checkpoints use a flushed temporary file, valid-primary backup and rename. Load validates schema/types/ranges and tries the backup. The world validates restored map bounds/collision. If neither save is valid, it runs a temporary unsaved session and preserves the original files. Closing mid-battle resumes from the last completed checkpoint; battles themselves are not saved.

## Acceptance and tests

- Existing movement stress, NPC and classic-map/zoom suites remain required.
- `battle_menu_test` verifies original composition, targeting, cancellation and unavailable actions.
- `mvp_ui_smoke` sends actual mouse/key input through player→pet targeting, cancellation and input isolation.
- `mvp_rules_test` covers progression, captures, pet skill, inventory, quest idempotency, malformed saves and backup recovery.
- `mvp_balance_test` completes the public-API adventure without direct profile mutation and checks full save/reload equality.
- `mvp_journey_test` traverses the actual shop/portals, village quest/recovery, capture/follow/name, progression, boss and reward, then restores the same interior position and companion. Corrupt originals are preserved.
- Python importer fixtures cover decoder and wilderness bounds/collision/malformed input. Rendered original battle and adventure menus are visually reviewed.

Run `scripts/test.sh` and the Python test suite described in the root README. No multiplayer, parties, families, external services or payment systems are introduced.

## World and battle motion fidelity follow-up

- Empty map surroundings now clear to black. A click beyond a blocked/non-floor target advances toward it up to collision, allowing a click outside the shop doorway to cross its original warp cell. `map.cpp:getRouteMap` (3551 onward) supplies the directional-routing reference; the current bounded grid fallback is not a complete port of its obstacle-steering algorithm.
- Doorway warps use `classic_map_transition.gd`: vertically compress to the center, replace the map, then expand. Reference: `process.cpp` cases201/204 and `produce.cpp:ProduceCenterPress`. Input is locked through the transition. The reference fork disables the effect dispatcher with `no = -1`; this project deliberately restores its source-defined effect, with configurable modern timing.
- Battle entry uses verified sound215 (`sas_15.wav`, `process.cpp:681`). No ordinary map-transition sound has been verified or invented.
- Regression coverage includes actual outside-floor shop clicks, collision/corners, modal input blocking, and animated battle/portal journey completion. Verification launches remain silent.
- Battle motion follows `oft/oft.cpp`: appear state uses original walk clips and off-stage ±300 offsets (`VCT_NO_APPEAR`, around10192/11440/12001); melee approaches to64px, plays the original attack clip, then walks home (cases1/2/14 around6300/6430/7660). The menu slides in after arrivals. Falling entry tiles follow `ProduceHagare(mode2)` with8×8 pieces and accelerating downward release. Animation timing is adapted to elapsed seconds, and the falling order is seeded; this is a supported subset, not a full port of every original battle action. Result dismissal stays locked until the sequence finishes.
- Remaining battle presentation gaps: special/projectile attacks and the pet command-panel entrance are not fully ported. MP gameplay remains absent; the original player HP frame is used without inventing an MP value.

## Level-up, defaults and development shortcuts

Player levels award3 spendable points across vitality/strength/toughness/dexterity (reference `battle.c:3168–3173`, `char.c:1853–1879`). Allocate in the original status window; save/load validates and retains the budget. Older profiles retain earned derived stats and receive their missing points once. Current effects are simplified primary gains (+4HP/+1attack/+1defence/+1speed); historical cross-stat formulas remain deferred. Pet automatic growth is unchanged.

Battle selection starts on attack (`battlemenu.cpp:186`) and restores player attack/capture and pet attack/skill target selections (`3665`, `593–612`, `3630–3642`, `3800+`). A target click is still required. Invalid choices fall back to attack; consumables do not replay automatically. Guard/escape return to the attack default.

Losing focus releases held keys but preserves click-to-walk routes and pending NPC approach. Explicit cancellation still clears routes. The separate DEV toolbar has a session-only **传送模式** toggle: Villager/adventure/shop shortcuts teleport when enabled and walk when disabled. **立即遇敌** uses the normal encounter flow, moving to wilderness if needed, and cannot reset an active battle. These shortcuts intentionally accelerate testing, not normal progression.

## Combat and equipment corrections

- HP meters follow `battlemenu.cpp:HpMeterDisp`: frames26019(player),26020(own pet),26014(other), actor anchor y−80, green40×2 fill. Authoritative per-action HP snapshots update meters on impact. Defeat returns automatically after the final animation.
- Combat selection/cancellation routes original217 (`sas_17.wav`); restricted bottom tabs use220 (`sas_20.wav`). The bottom bar stays visible on hover during battle. `menu.cpp:9864/9993/10036/10104` rejects field status/pets/inventory/map in combat; system music control remains available. Save and world mutations stay blocked during combat.
- Earned stat budget is3×(level−1), with remaining derived from four spent counters. Stale/missing remaining counters repair without refunding spent allocations; impossible over-allocation is rejected.
- Quest boss now72HP/10attack; a level-two player/pet withclub and allocated points wins30 seeded balance runs without potions. Enemy selection samples living player/pet targets, excluding fainted pets; guarding pets intercept. This is project balance using the live-target/random pattern in `battle_ai.c:355–396`, not full historical AI.
- Original classic equipment art26060 contains five slots, not a separate mannequin. `menu.cpp:InitItem` puts the ARM slot at(61,129); club bitmap offset(−12,−11) yields(49,118). Double-click bagclub equips, double-click equippedclub unequips. Inventory authority stores owned totals; the bag subtracts one equipped copy while retaining spares. No duplicate item is created.

The source-led [battle fidelity audit](../reverse-engineering/battle-fidelity.md) tracks weapon variants, pet selection, hit effects, results and remaining historical differences. It supersedes earlier presentation-gap notes where implemented.
