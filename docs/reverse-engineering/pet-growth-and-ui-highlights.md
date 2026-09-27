# Practical pet growth and native UI highlights

## Growth prediction

Sources in `references/chenmingbiao-stone-age/gmsv/`:

- `char/enemy.c:777–804`: rank comes from the nominal species weight sum.
- `char/enemy.c:1042–1075`: four independent birth variations from −2 to +2, then ten shared random initial allocations and the species initial coefficient.
- `char/char_data.c:1200–1267`: each level distributes ten picks among four attributes, draws **one shared** rank-dependent factor, and truncates each base increment.
- `include/char_base.h:41`: this branch's level cap is140. The UI's120 is a comparison target, not a claim about the original cap.

`pet_growth.gd` retains the exact expected truncated base increments. Its variance enumerates all286 legal multinomial allocations and51 factor outcomes; computing each derived stat's weighted sum before squaring includes both negative allocation covariance and shared-factor covariance. Independent future levels add their variances. The displayed likely interval uses a normal approximation (1.64485 standard deviations), then integer rounding; coarse derived stats can have more than90% coverage. Each stat's interval is marginal, not a promise that all four land inside simultaneously. Close to the target level the approximation is less reliable; zero remaining levels has no uncertainty.

The same-species comparator averages all five birth variations per stat and the shared allocation expectation, followed by expected normal growth from level1. Final derived rounding can move this mean by about one point. It is not a perfect-roll maximum. Hover that comparator to see the retained theoretical **individual-stat** bound; those extrema cannot all occur together.

The forecast conditions on this pet's actual current base and inherited weights. It never reads future RNG seeds, rerolls pets, changes saves, or promises the historical game's exact random sequence. GM/legacy offsets are included and clearly flagged as unsuitable for natural-quality comparison. Rebirth and special growth modifiers remain outside this model.

The initial seeded pets illustrate why the previous comparison was misleading:

| Pet | Lv120 HP/ATK/DEF/AGI forecast | Ordinary species mean |
|---|---|---|
| Blue dragon |1154 /260 /171 /126|1216 /273 /162 /138|
| Golden tiger |1044 /227 /167 /198|1036 /228 /167 /192|
| Red rex |1194 /266 /192 /174|1130 /269 /179 /162|

The blue dragon rolled lower vitality/strength/dexterity and higher toughness; the tiger and rex have different trade-offs. These are ordinary seeded original-rule births, not maximum-quality gifts. Existing saves are untouched.

## Interface highlighting

Sources in the local `anson1788-stoneage` client `system/`:

- `menu.cpp:9029–9043`: `MakeHitBox` draws an unfilled hover rectangle.
- `menu.cpp:16320–16323`: selected inventory item has a persistent `SYSTEM_PAL_AQUA` outline; `16358` uses a separate hover rectangle at center−24 to center+(26,23).
- `menu.cpp:12663`: pet names use font `hitFlag=2`.
- `mouse.cpp:287–303,335–339`: checked branch's hover cycle is palette250 for45 ticks,15 for5,2 for5,15 for5.
- `mouse.cpp:354–380`: selectable text outline surrounds its text, not the whole pet row.
- `mouse.cpp:490–538`: selectable sprite outline extends two pixels beyond its bounds.
- `systeminc/directdraw.h`: selected-item aqua is index254. The imported palette confirms this checked branch's250/15/2 are green tones. Other historical branches may differ; the yellow map marker25001 is separate.

`legacy_ui_highlight.gd` redraws these primitive outlines without adding fake sprite assets or intercepting input. Inventory selection distinguishes an equipped weapon from its spare bag copy. Buttons retain normal art on hover and their original pressed art on press; disabled buttons receive no actionable hover. Pet names, native pet buttons, status/shop native buttons, and top/bottom menu buttons use appropriate text/sprite bounds.

Validation:512 independent119-level authority growth paths, unchanged-save checks, and pointer-driven item/pet/menu tests including separate hover/selection, equipment/spare selection, and disabled/pressed states. All test runs are muted.
