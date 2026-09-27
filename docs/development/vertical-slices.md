# Next runnable slices

M000 village, M001 conversation and M002 classic HUD/map are already implemented within their documented scope. Do not repeat them or reuse their IDs for server integration.

| Slice | Demonstrate | Relative planning points |
| --- | --- | --- |
| Local movement authority | Existing walking through one owner; reject wall/bounds violations | 0.5–1 |
| Interaction authority | Existing villager only talks when reachable and nearby | 0.25–0.5 |
| One original interior | Enter one doorway and return to a valid exterior spawn | 0.5–1.5 |
| One encounter trigger | Enter battle state once; suppress repeated triggers while busy | 0.5–1 |
| First battle | One enemy, attack/guard, HP, win/lose, return to village | 1–2 |
| First pet | Capture/obtain one pet, show ownership, use it in battle | 1–2 |
| First save | Restart retains position and one progression field | 0.5–1 |

These are subsets of catalogue systems, not additional costs to add to those estimates. New rules go through Godot authority. Introduce abstractions only with their first demonstrated consumer.

After a portal works, add preload/cancel/failure behavior. After a battle works, expand targeting, skills, statuses and parties. Add the headless/network adapter only when testing two players. Each checkpoint keeps the original-resource Samgir playable.

The fun-first MVP now takes priority: [M003 battle](m003-first-battle.md) is implemented. Those steps are now delivered in [M004](m004-single-player-mvp.md). Further work should prioritize observed playtest issues and additional original fidelity/content before networking or a full NPC census. The rows above remain reusable system slices, not the current execution order.
