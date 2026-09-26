# Classic and modern presentation

Use one client, shared state, and shared interaction semantics. Presentation differences are preferences over the same simulation.

| Area | Classic intent | Modern intent |
| --- | --- | --- |
| Visuals | Preserve verified sprite proportions and composition | Optional scaling, clarity, and effects |
| Interface | Familiar compact arrangement | Resizable, readable panels |
| Movement input | Familiar interaction when established by evidence | Keyboard first, later optional click/touch |
| Map change | Optional classic fade/black transition | Preloaded doorway/camera transition |
| Audio | Original material where available and suitable | Independent volume, optional revised mix |

Classic does not imply verified compatibility with every historical build. Document the exact reference used. Modern does not silently change speed, collision, encounter rates, stats, or rewards. Such changes require a distinct ruleset/profile.

For M000 implement one coherent presentation with minimal controls. Add a mode switch only after two meaningful presentations exist. Shared accessibility settings include remapping, readable scale, mute, and reduced motion.

Acceptance for the eventual switch: current player state and profile identity remain unchanged; UI focus and controls work; animation/audio continue without duplicate instances. Apply scene-heavy changes at a safe boundary if live switching would disrupt play.
