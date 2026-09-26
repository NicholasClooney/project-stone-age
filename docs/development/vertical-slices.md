# Vertical slices after M000

Each row is a focused task; split again if it cannot leave a runnable checkpoint.

| Slice | Implement | Show / verify |
| --- | --- | --- |
| Directional polish | Replace temporary art with correct facing/frame mapping | Turn, walk, stop in each direction |
| Collision fidelity | Trace one building and its doorway | Wall blocks; entrance remains reachable |
| Swift connection | Handshake and initial position in the existing scene | Correct profile accepted; mismatch explained |
| Swift movement | Move intent → validation → accepted position | Server rejects walking through one wall |
| NPC | One actor, proximity check, short dialogue | Approach, interact, dismiss, leave |
| Basic interior | One explicit portal and destination scene | Enter and return to valid spawn |
| Modern transition | Preload that scene while approaching | Warm crossing without black screen |
| Streaming resilience | Cancel stale load and retain current map on failure | Rapid approach/retreat; delayed or missing destination |
| Encounter | One marked trigger and encounter state | Trigger once; no repeated encounters while busy |
| Battle | One enemy, one command, one turn resolver | Win/lose then return to world |
| Pet | One pet definition and ownership action | Persist acquisition once saves exist |
| Save | One profile-bound save slot | Restart preserves progress |
| Second profile | Add explicit differing content/rule choice | Switch sessions without modifying engine code |

For M001, first run Swift as a separate process. Bundle it only after the client-server slice works. A network abstraction, persistence interface, or feature registry is complete only when used by a demonstrated path.

Legacy-client login, old-server connectivity, riding, clans, rebirth, and advanced magic are later capability slices. Their historical associations require evidence rather than assumptions based on an edition label.
