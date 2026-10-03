# Background automatic quests

The task helper owns presentation, not automatic execution. Close, Esc and the explicit minimize button hide it while retaining both a pending automatic map download and the server's current task. Ordinary one-off navigation retains its existing cancellation behavior. Explicit stop, manual movement, party conflicts, death/battle failure and save failures keep their authority-side protections. Supported tasks and original routes, eligibility, transactions and rewards are unchanged.

`quest_auto_chip.gd` is installed beside the helper in the persistent UI root. It reads `derived.quest_auto` and `derived.quest_helper` and survives map changes without storing gameplay state. While the helper is hidden, it shows the current step, opens the active task when its body is clicked, and offers an independent 44-pixel stop button through the existing travel controller/link request. Its width follows the viewport and it sits above visible `automation_chip.gd` bars. Offline stop is disabled until the connection returns.

Transport loss now detaches the live task instead of stopping it. A detached task keeps its original phase and step, and waits without expiring the landing timer or granting arrival. Existing battle settlement and safety checks still run. This is distinct from the existing restart/resume policy: no save version or resume schema changes. On reconnect, an existing game follows the snapshot's authoritative location before reporting it. A reloaded game uses its normal snapshot location restoration.

Only an actual `report_position` matching that authoritative location can bind the detached task to a new socket/client. ProfileHub routes the command to the authenticated profile's backend and overwrites the connection field; a client-supplied profile, quest id or socket tag cannot select another profile. Merely logging in does not confirm arrival. Explicit owner logout and switching roles continue to stop the task; any device authenticated as that profile can use explicit stop. The single-backend WebSocket server retains its existing shared-session trust model.

## Targeted verification

- `quest_auto_background_ui_test`: real viewport clicks at 1280×720 and 390×844, both local and backend-free remote; close followed by a server step and map confirmation; Esc; minimize; chip restore; independent stop; overlap avoidance; real clicks above an open inventory; actual socket loss, reconnection of the existing UI, and UI reload preserving the same task.
- `quest_auto_reconnect_test`: real original-channel defeat while detached; real authenticated WebSockets, disconnect waiting beyond 30 seconds, login without arrival, matching-location rebind, forged cross-profile requests, unauthenticated refusal, same-profile second-device stop and explicit logout.
- Existing helper navigation/split UI, automatic task, quest resume and adult resume suites cover cancelled one-off navigation, original transactions, save failures and battle/death protections.

Authorized pixel proof uses a real muted renderer offscreen:

```sh
STONE_AGE_PROOF_DIR=/private/tmp/quest-auto-background-shots STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -2000,-2000 --script res://tests/quest_auto_background_ui_test.gd
```

Screenshots and logs are not committed. Headless checks do not prove rendered pixels. Tests use isolated user directories and ephemeral ports; the main/live server and player saves are never used. Full-suite validation is left to the merge coordinator for this batch.
