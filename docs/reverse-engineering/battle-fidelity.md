# Battle fidelity audit

Target: the current single-player battle subset, grounded in the locally archived original client/server and the imported 2.5 asset pack. This is not a claim that every historical battle system has been ported. Source offsets refer to the archived revision recorded in `local-references.md`.

| Surface | Original evidence | Godot behavior / verification |
| --- | --- | --- |
| Entrance | `process.cpp:681`; `produce.cpp:ProduceHagare`; `oft.cpp:10192/11440/12001` | Original215 sound, falling8×8 tiles, diagonal walking entry, command slide; rendered stage captures |
| Equipment | `char_data.c:215–219/310–322`; `item.h` CLUB2 | Explicit three-avatar club mapping100002/100007/100012; complete imported idle/walk/attack/guard/death sets, revert when unequipped |
| Command defaults | `battlemenu.cpp:186/593/3630/3665/3800` | Attack initially selected; target click still required; remembered pet selection leaves alternate choices accessible |
| Target feedback | `mouse.cpp:287/493–538` | Flashing border around the actual eligible sprite; unavailable targets do not activate |
| Names / HP | `battlemenu.cpp:386–512` | Original meter frames and green fill; centered names; per-action HP values apply at impact |
| Melee | `oft.cpp:6300/6430/7660`; `pattern.cpp:219–223` | Approach64px, attack at frame hit marker, damage/death pose, reversed walk home; club frame sound2=`sap_02.wav` |
| Hit effects | `oft.cpp:1245–1288` | Normal red25507→25506→25505; guarded blue25504→25503→25502; target y−32 |
| Floating numbers | `oft.cpp:348–430/968`; `gemini.cpp:595–635` | Actual HP delta, font14, red damage/green healing at y−64; original speed24→0→24 motion and hold translated to elapsed time |
| Action words | `oft.cpp:446–481/1037–1055/8565+` | Original guard/capture/success/fail/escape art, source y−80 anchor; no invented critical effects |
| Results | `menu.cpp:19324–19430` | Original tiled5×6 result window/title26018; actual player/pet XP and level-up rows; sound211 on level-up,202 otherwise |
| Defeat | `oft.cpp:10220–10240` | Final death pose finishes before automatic village recovery; no confirmation required |
| Bottom menus | `menu.cpp:9864/9993/10036/10104` | Visible hover bar; field map/status/pet/item tabs reject combat use with220; system music remains accessible |
| Stat allocation | `menu.cpp:11716–11723/11801–11808`, imported ADRN offsets | Original UP controls, base values and26075 remaining-point header at source coordinates |

## Deliberate limits

- Historical tick movement is adapted to elapsed seconds. The fork disables its transition dispatcher; source-defined transitions are deliberately restored.
- Balance, capture threshold and simplified stat formulas remain MVP rules. No invented critical hit, miss, counter, projectile, magic, riding or full-party presentation without matching authority rules.
- Capture uses the original walk/attack approach and action words; its complete captured-enemy follow choreography is not yet ported. Escape and every exceptional battle command are not complete state-machine ports.
- One active pet and one opponent; full historical formations and pet switching during combat remain beyond the current simulation.
- Assets and source versions differ. Match asset metadata and the chosen historical mode; never infer a new skin or sprite number from appearance alone.

## Acceptance gate for future changes

1. Trace source action/state and graphic/sound IDs before changing presentation.
2. Record placement, sprite offsets, input/cancellation, animation and audio together.
3. Verify real input and authority-backed outcomes, including equipment and alternate pet choices.
4. Render and inspect entrance, approach, strike, return, HP/guard feedback and results. Keep test audio silent.
5. Update this audit when scope changes. Do not call a surface original merely because it uses original textures.
