# Verification and handoff

## Core manual smoke check

Launch Samgir, move in four directions, stop and observe idle, collide with the boundary and a building, listen for music/SFX, toggle mute, and restart. Capture actual behavior; do not claim unobserved audio or animation works from a screenshot.

For later slices check the changed path plus this baseline:

| Change | Meaningful additional checks |
| --- | --- |
| Server authority | Invalid move rejected, stale command handled, disconnect recoverable |
| Portal/streaming | Enter/return, rapid repeated crossing, failed preload, no duplicate player |
| Profile resolution | Unknown feature, conflicting override, missing pack, incompatible digest |
| Persistence | Reload, interrupted write, migration failure, duplicate reward |
| Protocol/importer | Captured fixture, truncated input, oversized input, unknown IDs |
| Battle | Fixed-seed resolution, illegal action, exactly-once reward |

Automate invariant checks where they prevent meaningful regressions. Avoid writing tests that merely restate scene wiring. For presentation changes, launch and observe them. For performance-sensitive loading, record frame-time behavior and hardware during cold and warm transitions before making claims.

## Handoff record

Include outcome, exact reproducible launch steps, controls, engine/toolchain versions, checks actually run, screenshot/recording path, remaining gaps, and next smallest task. Distinguish implemented, manually verified, automated, and unverified.

No fabricated command names: document scripts only after they exist. If the environment cannot run the client, say that visual acceptance is pending.
