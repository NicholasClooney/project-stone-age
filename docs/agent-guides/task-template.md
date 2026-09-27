# Task template

Copy and fill this for one runnable improvement.

```text
Outcome:
What the player can see/hear/do afterward:
Current working baseline and launch command:
Milestone / relevant docs:
In scope:
Deferred:
Inputs/assets and known substitutes:
Smallest implementation path:
Approximate productive-work budget and checkpoint:
Acceptance checks:
Failure/fallback behavior:
Evidence to capture:
Handoff: implemented, verified, remaining gaps, next task.
```

## Example: one shop doorway

Outcome: enter one Samgir shop and return to the same village doorway.

In scope: one trigger, one interior scene, two spawns, single transition ownership. Use local transition state if authority has not been integrated; otherwise require server acceptance.

Deferred: whole-world streaming, multiple shops, edition-wide portal extraction, seamless camera treatment.

Acceptance: entry works; return works; walls block movement; standing at the destination does not bounce immediately; missing destination keeps the current scene playable.

Evidence: a short enter/return recording plus actual checks run. Next task: preload this specific shop and remove its loading gap using the same logical transfer.

Avoid tasks such as “implement the complete world architecture.” Name the specific player-visible behavior and stop when its checks pass.
