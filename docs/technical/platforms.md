# Platform policy

| Component | Current target | Future target |
| --- | --- | --- |
| Combined Godot app | macOS, existing Godot 4.6 workflow | Other desktop client platforms when requested |
| In-process authority | Same macOS app | Same rules in a dedicated export |
| Headless Godot server | Deferred | Linux and Windows, plus macOS development |

Prioritize playable slices. Keep UI, native plugins, OS launch behavior and filesystem paths outside authority rules. Use portable engine APIs when practical; do not add speculative platform abstractions.

Godot supports headless operation, but our application ports are untested. Before claiming Linux/Windows support verify the pinned engine, plugins, resource paths/case, saves, networking, shutdown and packaging on each target. Do not block the MVP on these checks.
