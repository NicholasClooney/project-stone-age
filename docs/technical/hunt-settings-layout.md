# Hunt settings layout

The hunt window has separate settings (through y 540), bounded wrapped status
(y 548–628), and actions (y 640) regions. The enclosing ScrollContainer keeps
the whole window reachable on small viewports. Capture mode checkboxes use
short labels with separate visible explanations; the status wraps to the
available viewport width. Inputs and dropdowns are at most 330 pixels wide,
so each can fit completely after horizontal scrolling at 390×844.

The attribute page has its own settings scroll viewport below the title and
location. Moving its controls into the scroll content must use
`reparent(content, false)` before translating their page coordinates by the
scroll origin. The former default `keep_global_transform=true` already
translated coordinates by that origin; subtracting it again moved the first
rows above the viewport and leftmost labels to negative x, clipping text.
The scroll content receives explicit positive padding and a minimum extent;
its children never have negative positions. When switching relative/fixed
threshold modes, the checkbox must shrink to its new combined minimum size;
otherwise its old hit rectangle overlaps the fixed-value input. Highest values
use a compact visible caption, with the full condition retained in tooltips.

`hunt_settings_layout_test` instantiates the actual GameScene and local Backend
with profile persistence disabled. It checks nonnegative content coordinates,
separate interactive rectangles and status, every visible control's mobile
scroll reachability on all three pages, checkbox clicks, embedded dropdown
activation/selection, and an actual horizontal wheel event. Embedded popups
allow the same input route in headless and rendered runs; keyboard confirmation
is sent while the dropdown is open, before releasing the opener mouse button
(a fitted phone popup can cover that button).

For actual PNG verification, explicitly opt into the authorized graphical test:

```sh
mkdir -p /private/tmp/hunt-layout-shots
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 \
  --script res://tests/hunt_settings_layout_test.gd -- --visual-review
```

This uses the real Godot Compatibility renderer and viewport texture, with an
offscreen window and dummy audio. It writes fourteen PC/mobile screenshots to
`/private/tmp/hunt-layout-shots`; screenshots are verification artifacts only.
The phone is a real 390×844 Godot viewport with canvas scaling disabled, not
an image resized after rendering. Horizontal crops at intermediate scroll
positions are expected; controls can be scrolled fully into view. This checks
native GPU rendering, not a browser or physical phone. Capture-only destination
semantics are implemented and validated separately by server tests.
