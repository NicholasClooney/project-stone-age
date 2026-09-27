# Architecture — one Godot project

Decision, 2026-09-27: use Godot and GDScript for both client presentation and gameplay authority. This supersedes the earlier Swift server proposal. One app and one process come first; a dedicated server can later be exported from the same Godot project.

```text
Now:    input/UI → local commands → authority → state/events → presentation
                                      ↓
                              content + persistence
Later:  input/UI → network adapter → headless authority (same project)
```

Profile, battle, encounter, automation and save authority now sit behind this boundary: the game talks to `client/server/backend.gd` only through a link, in-process or over WebSocket (see [backend interface](backend-interface.md)). Movement remains in the existing controller and is reported, not validated.

| Area | Owns | Must not depend on |
| --- | --- | --- |
| Client | Input, original UI, graphics, audio, camera, interpolation, streaming visuals | Direct writes to authoritative state |
| Server/authority | Movement validation, map membership, battles, inventory, pets, quests, saves | Camera, UI nodes, textures, audio, rendering frame rate |
| Shared | Commands/events, content IDs, logical map geometry, profile definitions | Client scene paths or mutable client copies of authority |
| Transport | Deliver commands and results; later encode network messages | Gameplay decisions |

Keep the existing `client/` directory as the Godot project root. Introduce `client/server/`, `client/shared/`, and `client/network/` only as their first consumers arrive; the directory name does not make this a client-only project. Use GDScript classes for rules, with a small Node for session lifecycle if needed. No second Godot project or Swift package is required.

For the fun-first roadmap, the first authority slice owns battle commands and HP. Move movement and interaction validation behind the same architectural boundary as those systems need it. Preserve the controls and original appearance, then route NPC interaction through the same owner. Avoid empty service layers or an entire simulation rewrite ahead of a working consumer.

Resolve a session profile into rules revision, features, content hashes, and protocol revision. Presentation settings stay separate. Local and remote modes must run the same rules. A legacy protocol adapter is optional and distinct from Godot networking.

See [server rules](server.md), [local mode](local-server.md), [networking](networking.md), and the [feature catalogue](../product/feature-catalogue.md).
