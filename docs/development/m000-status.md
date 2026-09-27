# M000 implementation status

## Current playable slice

Run `./scripts/run.sh` from the game repository root, or double-click `Play Stone Age.command`. Godot 4.6 starts directly in the original-resource Samgir village. No Swift process or network service is required.

The user's clarification supersedes the early placeholder fallback: **original map art, sprites, animation, and music are required for this MVP**. The geometric placeholder scene was rejected and moved out of the tracked client.

Implemented: original village rendering, original eight-direction idle/walk animation, keyboard movement, click-to-walk, collision and map bounds, BGM loop, legacy SFX, mute/volume, camera/zoom, character switching, sit/wave, and reset to a valid spawn.

## Verification

- Imported all selected map/character textures with no unresolved graphic references.
- Rendered the live Godot scene and inspected original scenery, character, depth placement, and HUD.
- Automated real scene checks cover movement in all cardinal screen directions, corresponding original facing, idle/walk state transitions, actual idle frame changes, collision, map bounds, route completion, invalid destinations, 200 repeated steps, character switching, sit, BGM loop boundary, mute, and input clearing.
- Binary decoder tests cover supported RLE commands and reject truncated, oversized, and invalid runs.
- Audio playback/loop state is verified in Godot; no claim of a calibrated listening comparison against the historical Windows client.

## Reported closure during movement

The first visible original-resource window was launched by `tests/capture.gd`. That test intentionally saves screenshots and exits after a short interval. Its process exited cleanly and no new Godot macOS crash report was found. The player was then relaunched with `scripts/run.sh`, which has no automatic timeout.

A separate system-font error was found in the persistent session and fixed by bundling an explicit Chinese font. Keep test capture launches clearly separated from normal play. Final movement checks must report zero failures and no Godot error lines.

## Remaining scope

The scene uses historical resources from a community client and server map, not a certified official-build recreation. The original-resource HUD and map window are now available; see [M002](m002-classic-ui.md). One verified village conversation is now implemented; see [M001](m001-village-npc.md). Interiors, persistence, Swift authority, and multiplayer are not implemented. Imported assets remain local; a fresh clone needs the documented import step.

Next slices should build on the working village and its NPC interaction. Do not replace the legacy artwork or music with approximations.
