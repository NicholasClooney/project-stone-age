# Capture progress viewer controls

`showcase_ticker.gd` keeps server log projection unchanged and adds local folded
and dismissed states. An inactive-to-active workflow transition resets these
states for the next run. Idle publications do not reopen a dismissed result.
The controls never call the session, link or automation commands.

Both expanded and folded views stay below the top-left status text, clamp width
to the viewport, and yield to task, inventory, collection and helper menus.
Existing bottom-right automation bars retain their positions. Buttons have a
44px minimum target height. State is local to the current client lifetime;
reloading a page can display the latest stored log again.

`showcase_panel_ui_test.gd` uses real GameScene widgets, injected presentation
snapshots and mouse events at 1280x720 and 390x844. It checks fold/restore, stopped
close, repeated idle publication, next-run restoration, wood permit status in the
current-task UI, quest helper input above inventory/pet collection, the game-helper
entry, and three simultaneous progress widgets. Workflow snapshots in the layout
segment are fixtures, not a claim that mutually exclusive server automations run
concurrently. The original source status and Jan transaction suites cover the
state fix separately; hunt_status_throttle_test covers two-device log publication.

Offscreen rendering command (only with explicit visual-test authorization):

```sh
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/showcase_panel_ui_test.gd -- --visual-review
```

Screenshots are untracked under `/private/tmp/ui-panel-followups-shots/`.
The task helper input-order fix is supplied by the separate automatic-task change
(`87f3006`); this change does not rewrite shared menu controllers.
