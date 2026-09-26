# Godot client

Use Godot for the 2D client. Proposed starting language: GDScript. Pin the installed engine version in the eventual repository; verify APIs against that version when implementing.

## M000 scene responsibilities

```text
Samgir scene
├── Map visuals + solid boundaries
├── Player: movement, facing, idle/walk state
├── Camera
├── Audio: music and one-shot SFX
└── Minimal controls/status overlay
```

Use the simplest supported tile or sprite composition for available assets. A reconstructed image with a collision overlay is acceptable for the first slice. Avoid building a general importer in the gameplay task.

Keep logical coordinates separate from screen projection. Store actor foot position for collision and depth sorting. Let map geometry determine projection; do not assume a square screen grid matches the source world.

## After server integration

Input creates movement/interaction intents. The connection delivers authoritative snapshots or events. Scene nodes display these values; UI never writes directly into inventory, quest, or battle authority.

Start with authoritative movement and interpolation. Add prediction only after local-to-remote latency makes it useful, with sequence numbers and reconciliation. Keep the M000 local driver as a clearly labeled development mode, disabled for remote sessions.

Verification: identical movement controls work with the development driver and the Swift connection; blocked movement does not continue animating translation; mode changes do not recreate domain state.
