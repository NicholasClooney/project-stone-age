# M004 — Single-player MVP

This checkpoint completes the agreed narrow playable loop. It supersedes M003's no-progression/no-save limitations; M003 remains a record of the earlier slice.

## Delivered loop

| Feature | Working scope |
| --- | --- |
| World | Original Samgir, 96×96 Sainas wilderness area, original30×30 item-shop interior and verified portals |
| NPCs | Existing original villager dialogue plus quest/recovery choices; original shopkeeper behind the original counter |
| Original battle menus | Native2×4 panel, original offsets/art, hover/pressed states, target selection, right-click/Esc cancellation, player→pet command phases, original item and pet selection frames |
| Battle | Attack, defend, escape, capture, potion; one enemy, one active pet; speed-based turn order, guard applies at round start; win/capture/escape/defeat; stronger quest encounter |
| Progression | Player and pet XP/levels, automatic growth, gold rewards; club improves attack |
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

Balance tests complete the core loop in7 encounters/25 turns, including all3 captures. That is a test route, not a measured20–30minute playtime guarantee. Walks, recovery and menu use add time; wider content and pacing remain future iterations.

## Original-flavor evidence and limits

- Battle base25116 and all8 command offsets follow the original `battlemenu.cpp` final panel anchor (player680,65; pet675,48 in800×600). Source references: lines3608–3609,3757–3765,3800–3801,3896; right-click cancellation337–339/3730. Original pet base25140/skill25141, item26061/title26072 and skill-selection26130 are used. Magic/help remain inactive in this scope.
- Status26073, pets26044/26045, equipment26060, inventory26061 and shop26138 are imported and populated against their baked labels. Unimplemented original status fields remain blank/dashes. Slot counts/stacking and automatic growth are deliberately narrower than complete historical behavior.
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
