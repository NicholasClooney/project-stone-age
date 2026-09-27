# Classic physical combat restoration

The local authority resolves each actor and impact before the presentation plays it. `turn_frames` includes actor, enemy/target/pet indices, outcome, damage, and full enemy/pet HP snapshots. Presentation must never manufacture a critical hit or subtract guessed damage.

## Source and selected profile

Reference: `references/chenmingbiao-stone-age/gmsv/`.

| Behavior | Source | Restoration |
|---|---|---|
| Dodge | `battle/battle_event.c:667` | Agility/type scaling, square-root probability, luck, 75% cap; guarding cannot dodge. |
| Physical damage | `battle/battle_event.c:1041` | Piecewise damage and original 1/16 attack variance. Neutral elements, no riding. |
| Critical hit | `battle/battle_event.c:1136`, `:1267` | Original probability; bonus is target defence × attacker level / target level × 0.5. |
| Guard | `battle/battle_event.c:1013`, `:1470` | Weighted retention of 0/10/20/30/40/50% damage; tiny damage resolves to 0 or 1. |
| Counter | `battle/battle_event.c:1205`, `:2770`, `:2911` | Agility/weapon probability, attack-command eligibility and 75% damage. |
| Counter chain | `battle/battle.c:6493` | At most five alternating reactions; every reaction has its own presentation frame. |
| Two attacks | `battle/pet_skill.c:573`, `battle/battle.c:6163` | Skill 10: two independently resolved strikes, each divided by two. |
| Guard break | `battle/pet_skill.c:1145`, `battle/battle_event.c:1446` | Skill 3 skips guard reduction. |
| Power balance | `battle/pet_skill.c:726` | Skill 50 uses executable data: +25% attack, −35% defence for that round; integer adjustments truncate separately. |

`combat_profile = "classic"` is the default, explicitly selecting the older source branch: defence contribution is `0.45 × defence + 0.2 × speed + 0.1 × vitality`. `"reference"` selects `0.70 × defence`, matching the reference server's enabled `_BATTLE_NEWPOWER` switch (`include/version.h:96`). This choice is not a claim that every historical server had identical tuning.

## Pet and enemy flow

- Encounters contain one to three enemies. Target selection is independent for player and pet.
- Pet **待机** is original `PETSKILL_None`: skip that action while remaining on the field. Normal defence does not intercept attacks on the owner; that belongs to the separate 忠犬 skill.
- Switching or withdrawing consumes the player's turn; an incoming pet cannot attack that same turn.
- Captured enemies leave the formation while surviving enemies continue fighting. Capture capacity includes captures already made during this encounter.
- The final result preserves every roster member's remaining HP and awards rewards only for defeated enemies.
- Learned skill IDs are authoritative. Levelling alone does not grant a fabricated double-damage attack.

## Verification and limits

`classic_combat_test.gd` exercises indexed capture, roster capacity, switch/withdraw/return, independent targets, two-strike frames, original probability calculations, and seeded misses/criticals/counters. `battle_rules_test.gd` retains deterministic replay, terminal-state, guard and actor-order checks.

Elemental adjustments, riding, ranged weapons, status effects and the rest of the original skill catalogue are outside this physical-combat subset. Capture chance and escape escalation remain the explicitly documented early-game rules. Enemy encounter composition and formation size are a playable subset, not a complete reproduction of historical encounter tables. Classic and reference profiles currently share neutral elemental treatment.

## Native formation and hit timing

Client `oft/oft.cpp:11409–11599` constructs the four rows; `monster_place_no` at line 144 reorders each row center-first. `system/main.cpp:1605` sets 800×600 displacement to `(160,120)`, applied only to the friendly rows. With the optional 6v6/40-character flags disabled, player slot 0 is `(677,504)`, pet slot 5 is `(581,432)`, and enemy slots 10–12 are `(101,150)`, `(69,174)`, `(133,126)`. Server `battle/battle.c:945` fills enemy slots from zero on their side, while a pet occupies its owner's slot plus five.

Critical stars (`oft/oft.cpp:1200,1242`) use the attack's hit-stop lifetime, not a separate arbitrary 16-tick duration. `HIT_STOP_TIM` is 8. A lethal-hit flag extends it to 32 (`:6982`). Five stars start at target Y−32, travel in directions `d0*6` for `d0=5..1`, and change sprite 25501→25500 halfway through their life. These are legacy update ticks; the Godot presentation documents its timing adaptation.
