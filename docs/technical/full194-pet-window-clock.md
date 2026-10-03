# Full194 pet portrait clock sampling

Baseline: integrate/stage-three `7b358be3618e82b1b74406c8cedb8ff234dcd535`.
This is a test-only correction; `animated_portrait.gd`, shared clocks, visibility,
texture loading and approved stage-three activation are unchanged.

The full-run failure was `portrait frame follows the shared clock`. That same
run passed animation advancement, facing changes, rebuild phase and animation
after rebuilding. The portrait's `_process` calls `_update(Time.get_ticks_msec())`
and uses that timestamp to choose its frame. An unavailable texture intentionally
retains the previous frame, but this run had the native portrait and subsequent
animation working. There is no evidence of a product clock-source change.

The test awaited `SceneTree.process_frame` twice, then compared the image to
clock values at now, now-20, now-40 and now-60ms. `process_frame` fires before node
processing. Awaiting it twice does not make the previous node-process timestamp
less than60ms old, especially during real scene/texture work. Its stated
"one frame of lag" was therefore implemented as an unrelated wall-time bound.
The untouched suite passed when run alone; this does not classify it as flaky
or justify retrying the failed full run.

The corrected suite brackets an actual automatic portrait process pass with
lower/higher-priority test nodes and records its displayed image and clock
interval together. The assertion uses only that recorded interval, not the later
coroutine's current time. Every timestamp the production `_process` could have
read lies within those endpoints; an unrelated frame outside this interval still
fails. The probe also checks visibility and automatic processing. The rebuild
assertion brackets the actual synchronous menu rebuild, whose setup selects a
frame from the same clock. It does not manually call the portrait update, freeze
its clock, set its image, reset its phase, or accept any arbitrary frame.

Observed passing run: actual process interval5476–5559ms, image95932; the test
coroutine resumed285ms after the interval ended. Sprite100250 standing3_1 has
1000ms duration and six images95929…95934. The actual interval allows95931 or
95932. Applying the old0/20/40/60ms samples at the later5844ms read yields
95934/95933/95933/95933 and excludes the valid recorded frame. This is concrete
sampling-latency evidence, not a proposed larger tolerance.

Both original3-second animation-advance bounds and all menu, facing, rename,
active-pet and storage assertions remain. The process observation is condition
based with a3-second bound; no fixed delay was added and no suite timeout or
full-run budget was increased. Only pet_window_test was run: untouched baseline
once for diagnosis and the corrected suite once, both0 failures. The full194
failure log remains the historical failing evidence. No repeated-green/full/live
or resource-import work was performed for this correction.
