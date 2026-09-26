# Audio

M000 requires one looping BGM track and at least one basic audible SFX. Prefer verified area music when available; otherwise use a clearly documented substitute. Do not stall movement implementation on an unknown legacy audio container.

Separate music and SFX volume controls. Avoid clipping by checking combined playback. Restarting a scene or entering an interior must not leave duplicate music players running.

Define audio by content ID with source, format, gain, loop start/end if known, and intended usage. Record any transcoding step and preserve original references. Map associations and authentic loop boundaries require evidence.

Footsteps, if used, trigger from actual movement at a controlled cadence; a blocked player must not produce endless steps. UI/interaction SFX are an acceptable first substitute when the historical game has no verified footstep recording.

For map transitions, retain a shared music identity where appropriate or fade/crossfade between tracks. Keep music continuity separate from scene ownership so unloading the source map cannot unexpectedly stop it.

Acceptance: listen to the loop boundary, verify one-shot retrigger limits, mute/unmute both buses, switch maps repeatedly, and check that stopping movement or closing UI stops inappropriate SFX. Record what was actually heard during verification.
