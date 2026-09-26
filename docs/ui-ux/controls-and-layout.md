# Controls and layout

M000 defaults: WASD and arrow keys for cardinal movement; a visible mute control; a short controls hint. Add an interaction key when an interactable exists. Define input actions centrally so later remapping does not modify game logic.

Two simultaneous directions resolve to the most recently pressed cardinal direction in the development profile. When a modal dialogue/menu owns input, movement stops. Losing window focus clears held movement to prevent a stuck key.

Click-to-move is a later slice: convert screen coordinates to logical map coordinates, find a valid path, and send normal movement intents. A click must not bypass authoritative speed, collision, or portal checks. Touch controls are a later platform-specific task.

Keep the HUD out of the character's central view. Use scalable text/panels, clear focus states, and visible interaction prompts. Avoid forcing original fixed-resolution UI layouts onto every window size.

Verify at a small and a large desktop window size, with keyboard-only use and UI focus changes. Do not add a launcher, account system, edition browser, or settings hierarchy before the direct-to-Samgir loop is working.
