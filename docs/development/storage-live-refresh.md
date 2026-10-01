# Warehouse live refresh regression

The three old minimize/refresh assertions required a replacement panel or scroll node. Current warehouse sorting deliberately reconciles the existing controls; replacement identity therefore no longer proves freshness. The tests now require stable controls plus authoritative counts, UID order, current stat cells, tooltip text and capacity-dependent withdraw buttons. Existing automation, release, scrolling and comparison checks remain.

Two product issues were exposed by stronger checks:

- `StorageSpecies` deferred reconciliation while its popup was open but did not schedule a retry. Closing it without a new state push could leave old rows. A single pending retry now reconciles the latest session snapshot after dismissal.
- `GamePanels.rebuild_keeping_scroll` scheduled restoration even when reconciliation kept the same scroll nodes. This could overwrite a subsequent user scroll with the old position. Deferred restoration now applies only when scroll controls were replaced.

`panel_refresh_test` constructs initial storage once, then uses real session retrieve, GM level and store commands to verify deletion, changed stats and insertion while preserving scroll. `remote_minimize_test` uses a port-zero real WebSocket backend and two clients: the second stores a pet while the first keeps its warehouse open beside an active hunt; the first verifies pushed content and withdraws the remaining exact UID after another UID is released. `automation_minimize_test` verifies real training changes player XP while warehouse rows and actions match the session. No backend gameplay method is replaced for these checks; the existing deterministic hunt source fixture remains unchanged.

Headless verification checks control data and interaction, not rendered pixels. No importer, real save, live server or foreground game is touched.
