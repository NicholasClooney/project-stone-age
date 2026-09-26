# Characters and pets

M000 needs only character identity, position, facing, movement state, and animation reference. Add stats, equipment, appearance choices, and progression when their first slice requires them.

Separate definition IDs from instance IDs. A pet species definition contains content/rules references; an owned pet instance contains identity, owner, progression, and mutable state. Rendering reads an appearance descriptor rather than deciding gameplay from a sprite filename.

## Later pet slice

1. Add one pet definition in the active content profile.
2. Implement one explicit acquisition action with server validation.
3. Show the pet in a simple ownership UI.
4. Save/reload ownership when persistence exists.
5. Add following, battle participation, or riding as separate slices.

Riding is a feature candidate with dependencies on pets, allowed mount definitions, and movement/animation rules. Do not assume every historical version or pet supports it. Disabling a feature must have a deliberate save-compatibility policy; never silently delete existing pets or progression.

Acceptance: acquisition cannot duplicate an instance; appearance changes do not alter stats; a disabled pet/riding feature rejects corresponding commands as well as hiding UI.
