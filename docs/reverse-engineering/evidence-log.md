# Evidence log and open questions

No legacy source tree or binary has been inspected as part of producing this documentation. The supplied conversation is design context, not verified protocol/resource evidence.

## Entry template

```text
Evidence ID:
Question / claimed behavior:
Exact edition, region, client/server build:
Source revision / file hash:
File and symbol, capture, or reference recording:
Method and reproduction steps:
Observed result:
Inference (separate from observation):
Confidence and unresolved alternatives:
Fixture / converted output:
Implementation consequence:
```

## Initial backlog

| Question | Status | Next useful experiment |
| --- | --- | --- |
| Exact Samgir map identity and geometry | Unknown | Render one candidate map and compare landmarks |
| Sprite direction/frame conventions | Unknown | Decode one character's idle/walk sequences |
| Samgir BGM identity and loop | Unknown | Compare one candidate recording with reference |
| Collision source and movement timing | Unknown | Trace one step and blocked step in a selected build |
| 1.82/2.5/5.x/8.5 feature differences | Unknown | Compare one system across two exact revisions |
| Legacy login and framing variant | Unknown | Trace encoder/decoder for a selected client/server pair |
| Linux/Windows Godot application support | Deferred | Audit only when that deployment is scheduled |

Link findings to the document and fixture they change. A design proposal can proceed with a labeled approximation while historical questions remain open.
