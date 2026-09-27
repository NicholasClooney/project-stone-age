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
| Capture | `oft.cpp:8565–8795` states35–46; `t_music.cpp:2783`; `sndcnf.h:129–130` | Approach/attack, capture hit sound,60-tick pause, slower return with spinning follower; failure anger and target retreat; success255-tick happiness, original BGM0 and target disappearance |
| Escape | `oft.cpp:8797–8954` states50/52–54 | Running-in-place accelerates in11 eight-tick stages; success sends player/living pet offscreen; failure decelerates, shows failure and60-tick sad pose |
| Results | `menu.cpp:19324–19430` | Original tiled5×6 result window/title26018; actual player/pet XP and level-up rows; sound211 on level-up,202 otherwise |
| Defeat | `oft.cpp:10220–10240` | Final death pose finishes before automatic village recovery; no confirmation required |
| Bottom menus | `menu.cpp:9864/9993/10036/10104` | Visible hover bar; field map/status/pet/item tabs reject combat use with220; system music remains accessible |
| Stat allocation | `menu.cpp:11716–11723/11801–11808`, imported ADRN offsets | Original UP controls, base values and26075 remaining-point header at source coordinates |

## Deliberate limits

- Historical tick movement is adapted to elapsed seconds. The fork disables its transition dispatcher; source-defined transitions are deliberately restored.
- Balance, capture threshold and simplified stat formulas remain MVP rules. No invented critical hit, miss, counter, projectile, magic, riding or full-party presentation without matching authority rules.
- Capture follows the source failure-at-home branch. Random mid-return breakaway is deferred; follower translation and the eight-direction spin use elapsed-time interpolation. Escape gait acceleration is adapted to imported clip durations. The current game ends encounters on capture/escape, so the final confirmation remains a project flow choice. Advanced exceptional commands remain out of scope.
- One active pet and one opponent; full historical formations and pet switching during combat remain beyond the current simulation.
- Assets and source versions differ. Match asset metadata and the chosen historical mode; never infer a new skin or sprite number from appearance alone.

## Acceptance gate for future changes

1. Trace source action/state and graphic/sound IDs before changing presentation.
2. Record placement, sprite offsets, input/cancellation, animation and audio together.
3. Verify real input and authority-backed outcomes, including equipment and alternate pet choices.
4. Render and inspect entrance, approach, strike, return, HP/guard feedback and results. Keep test audio silent.
5. Update this audit when scope changes. Do not call a surface original merely because it uses original textures.

## Capture/escape verification

`capture_escape_test.gd` resolves success/failure through the real local authority and checks follower movement, original emotion clips, audio events, return positions, offscreen removal, input/result timing and fresh-battle reset. Rendered captures cover following, celebration, breakaway, successful escape and failure. No capture thresholds or escape probabilities changed in this presentation slice.
