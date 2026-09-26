# Iterative development

Always leave a runnable improvement. Approximately every 30 minutes of productive implementation should produce something the user can launch, see, hear, or interact with.

## Working loop

1. State one observable outcome and its acceptance check.
2. Run the existing baseline before changing it.
3. Implement the shortest end-to-end path, initially hard-coded if helpful.
4. Launch it and exercise the changed behavior.
5. Record the result and next smallest improvement.

Architecture should grow around demonstrated behavior. Introduce a reusable portal after one doorway works; introduce a pack resolver after one profile can load directly. Maintain boundaries through simple functions and clear ownership before creating frameworks.

Research and tooling may exceed one iteration. Time-box them around one question, preserve fixtures/findings, and keep a playable fallback. Report productive implementation time separately from installation, asset preparation, or blocked research.

Do not spend successive sessions on abstractions while the scene cannot run. If a refactor is necessary, split it so each intermediate state can still walk around Samgir. Do not delete the previous working path until the replacement passes the same smoke check.

Use [verification](verification.md) proportionately. Visual work needs an actual launch; an import/build success alone is not proof of gameplay.
