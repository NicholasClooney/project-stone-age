# Replication estimates

These are planning judgments calibrated to the user's completed **Samgir = 1** and **villager conversation = 0.5** anchors. Points express relative effort/uncertainty, not hours. The original 30-minute aspiration is not evidence that every point takes 30 minutes.

## Remaining system work

| Package | Points | Interpretation |
| --- | --- | --- |
| Core | 41.5–85 | Representative gameplay systems beyond current slices |
| Extensions | 21.5–52 | Conditional or mismatched later systems; provisional |
| Delivery | 11.5–26 | Remote sessions, operations and OS validation; defer until needed |
| Product | 7–16 | New architecture/product goals, not historical feature claims |
| Optional interop | 11–27 | Two baseline legacy connection directions plus one save schema; opt-in |

**All listed systems excluding optional interoperability: 81.5–179 points.** This is an additive scope envelope, not a promise of complete game parity or a statistical confidence interval. It assumes existing importers/assets can be reused, one chosen rules profile first, representative data fixtures, and tests within each row. Shared foundations are charged once; feature estimates assume their prerequisites already exist. Remote transport is charged in N01, not again in each social feature. The second profile belongs to P01. UI content belongs to its owning feature, not again to C20.

Do not interpret the lower bound as a first playable-game requirement. Begin with the small [next slices](vertical-slices.md); their points are portions of catalogue rows, not extra costs. Re-estimate after the first battle and first persisted inventory transaction, because the two current anchors do not yet measure those harder systems.

## Full content restoration is additional

The local server snapshot contains **700 files with an LS2MAP header** among 706 map-directory files and **183 `.create` NPC files**. These are file counts, not 700 validated unique maps or 183 NPCs/quests. No complete NPC-instance, quest-chain, species or skill-effect census has been validated. Different client/server revisions and missing assets can increase work substantially.

Use a pilot before giving a full-content total:

| Content task after its system exists | Provisional marginal points | Measure before multiplying |
| --- | --- | --- |
| Additional compatible map: import and spot-check spawns/collision | 0.1–0.5 | Unique maps, format variants, repairs needed |
| Static NPC placement with existing dialogue handler | 0.02–0.1 | Actual instances and text encoding |
| Quest chain using existing conditions/rewards | 0.25–1 | Chains, branches, custom mechanics |
| Pet/item/skill batch of roughly 20 compatible definitions | 0.25–1 | Definition compatibility; new mechanics are separate |
| Unsupported format or new behavior | Re-estimate | Capture fixture and identify missing rules/assets |

These marginal ranges are hypotheses, not calibrated throughput. If all 700 map files proved unique, compatible and in scope, map review alone would provisionally add 70–350 points; this arithmetic is a warning about content scale, not a commitment or a complete content estimate. First sample 10 maps, 20 NPC instances and 3 quests, record repair rate, then replace these ranges with measured estimates. Automate bulk conversion and test exceptions; do not charge repeated manual implementation for identical data.

Unbounded scope remains: every historical edition, exact balance across all skills, missing content, production concurrency, every GM command, full legacy packet parity and external payment services. “Replicate all features” needs a selected profile and completed coverage matrix before it can have a defensible final total.

## Definition of done and recalibration

Each accepted slice launches from the existing app, uses original assets/sounds where applicable, enforces rules in the authority once introduced, and covers its main failure case. Record the source build and any fidelity gap. Test stateful mutations, repeated commands and save boundaries; visually check original UI alignment and behavior. Keep the playable checkpoint and use a conventional commit.

The machine-readable [estimate ledger](feature-estimates.json) is the source for arithmetic; the [catalogue](../product/feature-catalogue.md) explains each scope. Update both together when changing scope. This review changes documentation only; no authority, network or new game feature has been implemented by it.
