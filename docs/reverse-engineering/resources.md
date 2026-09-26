# Resource format archaeology

Begin with one sample of each needed type, not a universal archive converter. Preserve source bytes and hashes so discoveries can be reproduced.

| Resource | Questions to answer | Verification artifact |
| --- | --- | --- |
| Archive/index | Entry offsets, sizes, compression, identifiers | Enumerated index with bounds checks |
| Map | Dimensions, tile order, layers, projection, flags | Rendered map plus collision overlay |
| Sprite | Palette, transparency, stride, compression, pivot | Known frame on contrasting backgrounds |
| Animation | Frame lookup, duration, facing, action states | Timed idle/walk playback |
| Audio | Container/codec, sample rate, looping, area association | Playable sample and loop note |
| NPC/items/pets | Encoding, field semantics, cross-references | Validated neutral data sample |

Read loader code alongside file samples where available. Propose a layout, decode the sample, compare against a reference render, and record counterexamples. Treat a successful decode of one file as a hypothesis until additional fixtures agree.

Converters must validate offsets and counts before reading or allocating, reject truncated records, and report unsupported variants precisely. Preserve unknown fields in intermediate metadata instead of silently discarding them.

Do not infer collision solely from tile appearance or animation speed solely from frame count. If a field cannot be verified, label the output assumption and isolate it for correction.

Acceptance: deterministic conversion reproduces a known visual/audio reference and rejects a malformed fixture without crashing. Promote the result into the [asset pipeline](../content/asset-pipeline.md) only after that check.
