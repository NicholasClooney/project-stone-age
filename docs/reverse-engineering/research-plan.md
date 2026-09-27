# Legacy research plan

Research exists to answer a specific implementation question. Unknown formats and legacy compatibility must not prevent the Godot-only Samgir baseline.

## Context from the source conversation

The conversation identified candidate legacy client/server repositories, GMSV/SAAC components, LSS/lssproto-related protocol code, and an SDL-based mobile client as potential references. Their contents, buildability, provenance, default ports, and claimed edition compatibility have not been independently verified for this documentation package. No such claim is an implementation guarantee.

## Prioritized questions

1. Can one Samgir map, one character animation, and one music track be rendered/played from available resources?
2. Which coordinate, palette, frame-offset, and collision conventions explain those fixtures?
3. What does one movement action do in the selected client/server build?
4. Which exact login/world-entry messages would a legacy adapter require?
5. Which rules/content differences justify a second version profile?

Trace legacy client resource loaders, projection, animation, and input code. Trace server dispatch into movement/map logic and account/persistence boundaries. Reproduce only the capability needed for the current slice; do not port the entire legacy process architecture into Godot.

For every finding store source revision, file/symbol or capture reference, observed behavior, confidence, and a reproduction method in the [evidence log](evidence-log.md). Separate direct observation, inference, and unknowns.

Time-box initial investigation to one fixture. If decoding remains blocked, preserve the sample/hash and question, return to a labeled reconstructed asset, and schedule archaeology separately. Do not claim official authenticity from a repository name or README.
