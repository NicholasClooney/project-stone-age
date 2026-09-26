# M000 — walking around Samgir

## Outcome

Within approximately 30 minutes of productive agent work, launch Godot into a playable 萨姆吉尔村 scene: visible map and player, four-direction movement, idle/walk animation, BGM, one basic SFX, and basic collision. This is a scope discipline, not a guarantee that missing tools or unknown asset formats can be resolved in 30 minutes.

Godot-only implementation is explicitly allowed. No Swift, login, database, network transport, general importer, or version-selection UI is required.

## Preconditions and asset fallback

Use an installed working Godot editor, a writable project, and a ready asset subset where available. Inspect only enough to identify a usable map, sprite animation, BGM, and SFX. If tools are missing, report setup time separately rather than claiming a playable result.

At minute 5, stop open-ended asset archaeology. Use a small reference-informed Samgir reconstruction, animated placeholder character, and available or original substitute audio if authentic assets are unavailable. Mark substitutes in the asset inventory and visible development status. A generic test grid is a movement prototype, not a faithful Samgir reconstruction. Record which map landmarks remain unknown.

## Suggested time budget

| Minutes | Work | Runnable checkpoint |
| --- | --- | --- |
| 0–5 | Open/create project; select assets and fallback | Empty scene launches |
| 5–10 | Assemble map/background, spawn, camera | Samgir representation visible |
| 10–18 | Add player, four-direction input, idle/walk states | Character moves and changes animation |
| 18–23 | Loop BGM; add one SFX and mute control | Audible interaction/movement |
| 23–27 | Add outer bounds and at least one obstacle | Player cannot leave playable area or cross obstacle |
| 27–30 | Run checklist; capture evidence; hand off | Demonstrable baseline with known gaps |

If time slips, shrink map extent and asset fidelity before removing core acceptance items. Keep each working checkpoint. Report unmet criteria honestly and finish the smallest missing behavior in the next slice; do not label an incomplete prototype “M000 complete.”

## Acceptance checklist

- [ ] Launch lands directly in a labeled authentic or reconstructed Samgir scene.
- [ ] One visible character spawns on walkable ground and stays in view.
- [ ] Arrow keys or WASD move north/south/east/west with consistent speed.
- [ ] Idle and walking are distinct animated states; stopping preserves facing.
- [ ] BGM starts, loops, and respects mute/volume.
- [ ] At least one audible movement, interaction, or UI SFX plays without uncontrolled retriggering.
- [ ] Map bounds and one solid obstacle block movement; diagonal input cannot bypass them.
- [ ] Restart returns to a valid spawn with no blocking error.
- [ ] Handoff includes exact launch instructions, controls, asset substitutions, and a screenshot or short recording.

Four directional animation sets are preferred; if art only supports fewer directions, keep four-direction movement and record the visual limitation. Do not describe a static sprite as an idle/walk animation. If authentic idle frames do not exist, use an explicitly labeled temporary animated idle treatment.

## Definition of completion

All behavioral checks pass. Record fidelity separately as authentic-assets, reconstructed, or placeholder-assisted. Completion of a placeholder-assisted M000 does not establish historical accuracy. The next task should improve one visible gap or connect the working movement slice to Swift.
