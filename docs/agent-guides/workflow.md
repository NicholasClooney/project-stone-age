# Coding-agent workflow

1. Read [README](../README.md), the current milestone, and repository-local instructions.
2. Inspect what actually exists; do not assume the proposed layout, scripts, assets, or server are implemented.
3. Run the baseline and choose one observable change.
4. Identify the shortest working path and a fallback for missing assets/tools.
5. Implement, launch, verify, and preserve the runnable result.
6. Update only the docs affected by a real decision; hand off with evidence and the next small task.

## Decision rules

- For M000, prefer direct Godot code over server or framework preparation.
- For subsequent gameplay, preserve Godot authority once integrated; temporary local state is a labeled development path.
- Keep edition rules, content, protocol, and presentation independent.
- Do not claim historical behavior without an evidence entry.
- Do not turn Linux/Windows support, embedded libraries, generalized streaming, scripting, or public-server operations into early gates.
- Stop broad refactors if they jeopardize the playable baseline; reduce scope and make an intermediate runnable change.

Ask for clarification only when a material unresolved choice changes the requested outcome. Resolve ordinary implementation details using the milestone's constraints. Report blockers precisely and continue independent useful work when possible.

A screenshot proves a rendered state; it does not prove animation, sound, networking, or persistence. Say which checks actually ran. Use the [task template](task-template.md) for bounded follow-up work.

For original-flavor battle/UI work, follow the [battle fidelity audit](../reverse-engineering/battle-fidelity.md) acceptance gate. Inspect source behavior, not only artwork; run silent input tests and visually review rendered states before claiming fidelity.
