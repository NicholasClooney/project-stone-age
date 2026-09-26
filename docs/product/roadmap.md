# Roadmap

Only M000 has an approximate time target. Later milestones are ordered outcomes, not duration estimates.

| Stage | Visible result | Completion evidence |
| --- | --- | --- |
| M000 | Walk around Samgir with sound and animation | [Acceptance checklist](../development/milestone-000-samgir.md) and short recording |
| M001 | Same scene driven by a local Swift server | Movement accepted/rejected by Swift; client-only baseline still available |
| M002 | Meet and talk to one NPC | Interaction distance checked; dialogue opens and closes |
| M003 | Enter and leave one interior | Correct map/spawn; basic transition works |
| M004 | Preload that interior for modern presentation | No black loading screen on a warm transition; slow-load fallback works |
| M005 | Trigger and complete one battle | Authoritative turn resolution and return to world |
| M006 | Obtain/use one pet and persist progress | Reload preserves pet and player state |
| M007 | Select two validated profiles | Different content/rules resolve without a code fork |
| M008 | Two clients share a remote session | Movement, transitions, and reconnect behave coherently |

Improve directional fidelity, collision, audio, and map reconstruction between milestones whenever they give the next useful visible improvement. Legacy-client interoperability is a separate research track and never a gate for M000–M004.

Keep each milestone decomposed into [runnable slices](../development/vertical-slices.md). Reorder later work when evidence or user priorities justify it; preserve the working Samgir baseline.
