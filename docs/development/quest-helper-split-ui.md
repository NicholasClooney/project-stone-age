# Quest helper split view

The helper uses the server's `derived.quest_helper.quests` projection. Desktop widths of 720 pixels and above show a task list beside the selected task's details. Smaller viewports use list → details → back, with the selected task and scroll positions retained. The current-task section stays above the scrolling remainder of the list; it has its own bounded scroll area when many tasks are active.

Grouping is deliberately conservative:

- **当前任务**: the server says `进行中`.
- **可接任务**: not completed or active, no server `blocked_reason`, and a current original `REQUEST` step explicitly has `actionable: true`.
- **未开始**: all remaining unfinished tasks, including unavailable tasks and tasks with unmet prerequisites. Details retain the exact server explanation.
- **已完成**: the server says `已完成`; original repeatability remains visible in details.

No task IDs are enumerated by the list and no reward/stat icons are inferred. New server entries appear automatically. Automatic execution remains restricted by the existing shared `quest_auto_policy.gd`; this change does not enable additional automatic jobs.

Only one task's steps are rendered in the detail pane. The current step is the initial action target; selecting another step exposes the same teleport and map-arrival/walk operations. The single pair of navigation buttons replaces a pair on every step. Original download, authoritative visit, confirmation and cancellation flows remain in the existing travel controller. UI state never mutates a backend. Stop stays above both pages during automatic execution or pending downloads. Close and Esc retain the existing pause/cancellation rules.

## Verification

`quest_helper_split_ui_test` drives actual viewport clicks against both a local game and an ephemeral WebSocket server with no client backend. It verifies 1280×720 and 390×844 layout, task selection/back navigation, conservative grouping, dynamic server entries, retained selection, step selection, 44-pixel controls, phone stop during a gated download, and Esc. `quest_helper_ui_test` and the existing original quest suites continue to exercise real teleport/walking, dialogue confirmations, automatic execution/stopping and late callback rejection.

For explicitly authorized visual review:

```sh
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/quest_helper_split_ui_test.gd -- --visual-review
```

This renders muted, offscreen native windows and writes PNGs to `/private/tmp/quest-helper-split-shots/`; screenshots are not committed. Headless geometry checks alone do not verify pixels. No live server ports or live saves are used. The full suite is intentionally deferred to the coordinating session for this batch.
