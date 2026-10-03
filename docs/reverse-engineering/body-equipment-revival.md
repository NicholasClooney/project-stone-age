# BODY equipment and original resurrection item

Source: local `references/chenmingbiao-stone-age/gmsv`, with the client target decoder checked against `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码`. These are pinned community snapshots, not a claim of complete official-version parity. No importer or reference asset is changed.

## Reviewed fields and coverage

| Item | Source row / zero-based columns | Enabled behavior | Deliberately still metadata |
| --- | --- | --- | --- |
| 1052 芙雷雅Lv1铠6 | itemset.txt:1053; type 19=7, level 22=30, durability 30/31=2500000, defence 39/40=20, speed 41/42=-6 | Independent BODY UID, Lv30, defence +20 / speed -6, ordinary defensive durability wear | magic 55=10 / probability 56=100 / MP 57=8 (滋润的精灵 Lv1) |
| 2450 萨顿家的秘药 | itemset.txt:2033; argument 3=500, function 10=ITEM_useRessurect, type 19=16, field 20=1, target 21=101, level 22=0 | Battle item, one owned UID consumed per executed use, resurrection roll 450–550 capped at max HP | No item magic expansion |

This adds **only 1052** to the reviewed wearable map and **only 2450** to the reviewed resurrection map. Existing reviewed ARM, HEAD, bracelet (including 1206) and amulet items retain their previously reviewed definitions. In particular, no automatic support is inferred for all type-7 armour, other missing slots, random stats, resistance effects, or the source's other resurrection items 1530–1532/1839. The three legacy BODY spirit items `haru_armor`, `freya_robe`, `teo_robe` remain supported and replace/share the same single BODY position with 1052. Existing HEAD/ARM/DECORATION1/DECORATION2 remain independent.

Current reviewed original equipment compatibility list (the rows other than BODY are existing coverage, not newly enabled effects):

| Slot | Original IDs |
| --- | --- |
| BODY | 1052 (new) |
| HEAD | 2418, 2605 |
| ARM | 2416, 2448, 2460, 2465, 2485, 2492, 2493, 2494, 2688, 2689, 2690 |
| DECORATION1 / amulet | 1357, 2427, 2487, 2489, 2505, 2606 |
| DECORATION2 / bracelet | 1206, 2481, 2491, 2765 |

## BODY ownership and migration

`item.h` defines `ITEM_ARMOUR=7`; `item.c:1234–1235` maps it to `CHAR_BODY`. The original five-slot frame places BODY at (134,129), independent of HEAD (136,59). Original equipment uses `original_equipment.body` as an instance UID; legacy BODY ownership stays in `inventory` and its selection stays in `equipment.body`. Equipping either representation clears the other's selection without deleting an owned copy. Bag-full unequip and replacement checks remain authoritative.

Save version 6 already supports optional equipment fields. A genuine pre-BODY v6 profile lacks `body` and contains an unworn metadata-only 1052 at durability zero; validation accepts that historical shape, then migration creates an empty BODY and initializes only that item's durability once. New profiles carry all five slots. Existing positive durability is never replenished; worn zero durability, wrong-slot UID, duplicate UID, simultaneous legacy/original BODY and underlevel worn BODY are rejected. Missing HEAD plus present BODY is not a genuine historical schema and is rejected. The maximum original-instance count allows fifteen bag items plus the actual supported original slots, while `bag_slots` still enforces the total bag limit. Pre-v6 ownership follows the existing migration.

Ordinary modifiers participate in admission stats, per-owner party stats, capture/stat projections, combat wear, destruction and settlement. BODY uses BATTLE_ItemCrush's defensive slot index 1; destruction strips modifiers immediately. UI emits only session commands. The separate equipment-save fix rolls equip and unequip back on failed disk writes.

## Resurrection targeting, death and consumption

- `item.h` defines field 1 as battle only, target 1 as OTHER. `netproc.cpp:1813–1819` splits 101 into target 1 plus `deadTargetFlag`.
- `battlemenu.cpp:1405–1440` checks usable field/level and enumerates every present actor on both sides for OTHER. The flag allows dead actors; it **does not exclude living actors**. The item has level 0 and no MP cost.
- `battle_item.c:606–654` parses the numeric argument, calls `BATTLE_MultiRessurect`, then unconditionally calls `BATTLE_ItemUseDelete`. `battle_item.c:17–47` deletes the selected item instance.
- `battle.c:514–562` enumerates a single actor 0–19 or a side for `BATTLE_MultiListDead`; `battle.c:4913–4935` requires a real participant, a battle mode other than absent/rescue, attackable status and the death flag. This implementation exposes only the item's single-actor OTHER form, never a client-selected whole-side code. Absent/escaped/captured actors and invalid target codes are refused without consuming when selecting a command. A valid queued target that leaves before execution still consumes the item, matching the unconditional source deletion.
- `battle_magic.c:1563–1673` ignores a living target and excludes a human target in P_vs_P (pets are not excluded). It rolls `RAND(power*0.9,power*1.1)` for nonzero power, applies at least 1, adds to HP and caps at max HP, then clears death. Thus **500 is the source parameter, not a guaranteed 500 HP**. The implementation's death representation is HP=0, consistent with existing battle actors. Its PvP eligibility predicate preserves the source restriction; no new PvP mode is introduced and clients cannot inject one.
- Friendly people, their participating pets and present enemy actors can be selected. A dead caster cannot act. A living target, or one already revived by a faster teammate, consumes the item with no extra healing: **原版行为**. Battle ending on the last enemy's defeat or the whole party's defeat remains unchanged; the item cannot reopen a finished battle.

Successful owned-pet resurrection in non-`norisk` P_vs_E records the original `AI_FIX_PETRESSURECT=300` variable-AI increase (`battle.h:450`). A server-created per-battle item budget bounds per-pet counters, party slices assign them to the pet owner, and settlement applies the gain once through the existing loyalty clamp. Failure rolls it back with HP and inventory. Client-provided budgets and risk/PvP flags are cleared at admission. The caster animation ID is the source `SPR_item3=100612`; the existing imported effect pack does not contain that sequence, so the caster flash is currently absent rather than substituted with a spell animation. The target resurrection sequence 100609 is imported and renders normally. This task does not run a shared asset importer.

The original function also parses `%`, and the shared source routine overwrites that calculation with its random-power branch. This task does not implement arbitrary functions, arguments or percent items. Only trusted 2450 power 500 is reachable. Existing field herb behavior and existing spell behavior remain separate.

## Transaction and network boundaries

Admission takes a copy of owned resurrection instances. Commands name `revival:<uid>` and a target; clients cannot choose an amount or submit a result inventory. `open_battle` first removes incoming resurrection-list/transaction/PvP fields and then copies trusted pending fields if present. Own-side target codes reuse view-relative 0–9; enemy codes 10–19 are decoded only by the item helper, checked against present enemy count and do not extend spell target codes.

The resolver removes exactly one UID from the caster's battle inventory. Each party slice carries only that participant's remaining instances. Settlement validates a unique subset of the admission list and removes the missing UIDs from the profile. Profiles containing any admitted resurrection item use the existing atomic settlement path. For a party containing such a participant, the host marks every participant's pending record atomic, including revived recipients who carried no item. The same authority predicate gates both settlement and close-retry.

Save failure restores profile, pending and capture events. Existing personal `party_settlement.result` and `drop_claims` remain frozen; retries reuse the original roll and consumption. Completed members cannot receive another payout. The transaction marker lives only in pending for this battle and clears on success. Existing capture-only, quest and stationary failure notifications are preserved.

Enemy revival preserves `loot_credited`, `killer`, battle UID and existing generated drops. Claims for a currently revived living or captured enemy are filtered from payable results, while the original internal claim remains associated with its first death. A later death does not create another claim or change party kill ownership. Final XP/gold still iterate each enemy instance once. This preserves the project's existing no-duplicate economic settlement boundary rather than adding repeated kill payouts.

## Validation and presentation

Dedicated suites: `equipment_save_atomic_test`, `body_equipment_revival_test`, `body_revival_authority_test`, `body_revival_party_test`, `body_revival_ui_test`; all registered in `scripts/test.sh`. Tests use isolated test saves and port 0. Coverage includes failed equip/unequip writes and old disk state, BODY migration and validation, ordinary modifiers and wear, field refusal, forged UID/config/PvP, living target consumption, actual pet/team resurrection, exact random bounds/max HP, personal party slices, per-member and simultaneous save failures, repeated failed close then success, frozen HP/RNG, original-item claim deduplication, final disk readback, and a second real WebSocket device replaying an old turn.

The mobile suite drives real clicks at 390×844 with a remote client that has no backend. It equips 1052 into the native BODY silhouette, opens 2450's scrollable description, selects the battle item and a dead pet, and observes the actual authority consume/revive. New phone resurrection controls have 44px rows and readable unscaled text; the existing battle canvas retains its native aspect ratio. Native muted offscreen rendering was explicitly authorized:

```sh
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/body_revival_ui_test.gd -- --visual-review
```

Six screenshots in `/private/tmp/body-revival-shots` cover BODY before/equipped, field medicine details, battle item selection, target selection and revived pet. Each was opened for pixel review. Screenshots and imported assets are not committed. This is a 390px mobile verification, not a claim of a full desktop/PvP/all-device visual audit. Only relevant suites were run; the coordinator owns the full-suite run and live relaunch.

Incremental estimate was provisionally 1.5–2.5 project SP, calibrated to original Samgir=1 and villager conversation=0.5. Reuses UID inventory, battle targeting, authority transport and settlement foundations; source/target audit, new BODY compatibility, per-owner item transactions and failure/mobile validation are this slice's incremental work. SP is scope/uncertainty, not elapsed time. Historical catalogue totals are unchanged.


## Desktop follow-up and source effect availability

The same real WebSocket UI suite accepts `--desktop` (1280×720). It clicks the native `choice_panel/OriginalRevivalItem`, verifies the corpse target is visible, enabled and inside the viewport, then sends actual mouse input to `target_buttons[2]`. The authority revives the owned pet and consumes one UID; a second socket replay is rejected and the saved profile reads back correctly. On 2026-10-03 this offscreen rendered run passed with zero failures:

```sh
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/body_revival_ui_test.gd -- --visual-review --desktop
```

Log: `/private/tmp/body-revival-desktop.log`. Six `1280-*.png` images in `/private/tmp/body-revival-shots` were individually opened for review. This confirms the desktop medicine/dead-pet click path, not an exhaustive desktop layout audit. The native medicine menu retains the existing small canvas-scaled presentation.

100612 is **available in the original pack**, but absent from the current imported index. Read-only decoding with the existing `Archive` and `import_battle.animations` found action `0_0`, duration 1500 ms, 14 frames, bitmaps 7232–7245, all decoded successfully. Source root: `.tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5`; animation files `data/spradrn_5.bin` and `data/spr_4.bin`, bitmap file `data/real_15.bin`. Evidence and decoded PNGs are isolated under `/private/tmp/body-revival-100612/audit.json` and its directory. Shared assets were not written.

The minimal supplemental import is to add 100612 to `tools/import_mirror.py:EFFECTS` and its provenance, then run that existing importer against the above source in the coordinator's asset checkout (or an approved cloned asset worktree). It emits the 14 PNGs and the `characters["100612"]["0_0"]`/image metadata consumed directly by `mirror_effect.gd`; no new runtime interface or magic implementation is needed. Its normal run also rewrites the existing mirror item images/manifest entries and effect index, so it must not run through this worktree's shared asset symlink. A full export was also validated under `/private/tmp/body-revival-100612/export` by extending the imported module's `EFFECTS` tuple only in the temporary Python process: 167 total effect PNGs exported, including all 14 new frames and matching index entries; log `/private/tmp/body-revival-100612/export.log`. No tracked importer or shared asset changed. Importer modification/asset regeneration remains a separately coordinated step; this follow-up commits only the desktop test option and source evidence.
