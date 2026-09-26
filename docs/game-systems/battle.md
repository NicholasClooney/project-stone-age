# Battle

Battle is deferred beyond the walkable village and first interactions. Begin with one player, one enemy, one legal action, and an explicit win/lose return path.

Proposed state flow: world → encounter pending → battle setup → collect actions → resolve turn → results → world. Prevent movement/interaction commands while battle owns the character.

The server owns participants, valid actions, turn ordering, damage/status calculations, random decisions, outcomes, and rewards. The client presents an ordered event sequence; animation completion does not determine combat results.

Keep formulas, pet participation, skill availability, and progression rules in a versioned ruleset. Use a deterministic prototype formula only under `samgir-dev` until historical behavior is verified. Record evidence before labeling a formula authentic.

Acceptance: fixed inputs and random seed reproduce the same result; illegal or repeated actions cannot resolve twice; win/lose returns to a valid map position; rewards are granted exactly once. Add disconnect/time-out policy before multiplayer battle, with a defined server decision rather than indefinite waiting.
