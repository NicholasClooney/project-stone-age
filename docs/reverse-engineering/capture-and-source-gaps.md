# Capture rules and current encounter-source gaps

Read-only audit of the pinned local reference, 2026-09-27. This records differences, not an implementation of the full capture formula.

## Sprite 100298

`gmsv/data/enemybase.txt:114` defines ordinary template114 **凯比特**; line469 defines special template668 **卡比特** (also called 风凯比特 in enemy records). Both use sprite100298. The ordinary template is capturable; the special one is not. The definition exists. Local asset extraction reports `RLE overrun` in `encounters/art-coverage.json`: this is an unresolved resource-decoding failure, not proof that the upstream definition is absent. Distinguish damaged bytes from an unsupported decoder variant before claiming a root cause. Runtime currently skips troops requiring this unavailable animation, with no substitute or reroll.

## Missing probability weights

These are blank selection weights, not a 0% encounter setting. C initializes the fields to −1 (`char/encount.c:164,297`; `char/enemy.c:626,650`). The defensive importer rejects selected malformed records instead of assigning invented weights.

| Record | Map / rectangle (inclusive) | Missing weights | Reference |
| --- | --- | --- | --- |
| Area41 | 萨伊那斯100: (587,331)–(630,343) | Groups158,162,166 | data/encount.txt:20 |
| Area42 | 萨伊那斯100: (532,332)–(595,361) | Groups158,162,166 | data/encount.txt:21 |
| Area43 | 萨伊那斯100: (524,325)–(546,346) | Groups158,162,166 | data/encount.txt:22 |
| Group125 | Areas45/66 on map100 | Enemy161 布伊 Lv9–11 | data/group.txt:35 |
| Group141 | Area46 on map100 | Enemy172 鲁尼帖斯 Lv13–16; enemy168 呼拔拔 Lv12–15 has weight1 | data/group.txt:50 |

Groups158/162/166 are 火鸡 Lv10–12, 奇宝 Lv11–13, and their mixed group. Areas41–43 list six groups but supply only three weights (20,20,20 for122/126/129).

The complete catalogue also includes malformed groups387 (`group.txt:276`, maps10404/10405),755 (`:632`, 蛮猪战队, no ordinary area reference),833 (`:670`, 精灵王黄人龙, item-gated map11201). These are outside the currently playable ordinary island scope. Do not describe125/141 as the only malformed groups in all reference content.

## Original capture sequence

Evidence: `gmsv/battle/battle_event.c`, capture handler around3115 and required-item check around3355; `char/pet.c:323` copies captured HP; `include/util.h:79` defines inclusive integer RAND. `_CAPTURE_FREES` and `_NEED_ITEM_ENEMY` are enabled in this checked reference.

1. Check species-specific required items where configured.
2. Target must be an enemy with the capture flag, and enemy level must be at most player level+5 (admin `CHAR_PickAllPet` can bypass the latter checks).
3. Compute float score:

```text
score = (10 − HP² / max(1, maxHP)
         + (playerLevel − enemyLevel) / 2
         + (playerDexterity − enemyDexterity) / 15
         + speciesCaptureValue + playerLuck)
        × playerCharm / 50
        + temporaryCaptureBonus
        + (enemyAsleep ? 15 : 0)
```

The species parameter is ADDED: higher means easier, despite the current importer field being named `capture_resistance`. No direct party or mount multiplier appears in this check.

4. Cap score at99; no lower clamp. Success requires inclusive integer `RAND(1,100) < score`. Strict comparison matters: score50 gives49%, score50.2 gives50%, maximum actual chance is98%. There is no universal fixed capture percentage. Remaining absolute HP matters through the squared-HP term, not just HP percentage.
5. Clear the temporary bonus after the attempt, including required-item failure. Successful acquisition still needs a free slot and successful pet creation.
6. Original capture preserves actual level, base stats and **current injured HP**; source also copies skills/status data.

## Current implementation boundary

At v0.22.0 eligible enemies at ≤60% HP always pass the MVP success check; enemies above it fail. This is a deterministic HP threshold, NOT a60% success probability. Original per-enemy capture flags are respected and captured level/base/growth are saved, but the original level gate and probabilistic formula are not yet restored. Captured HP is reset to full and skills are initialized empty. Full charm/luck/status/required-item integration is needed before claiming native capture parity.

Keep this audit separate from the battlefield-background bug fix; do not silently change capture behavior while answering a source question.
