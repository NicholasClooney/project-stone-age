# Arrival tests after final-chain activation

Baseline: `7b358be3618e82b1b74406c8cedb8ff234dcd535` on
`integrate/stage-three`. This change only adjusts the two owned test suites.
No descriptor, production policy, service or movement code changes.

## Root causes in full194

`quest_arrival_case_matrix_test` had ten failures: one obsolete planned-inactive
NPC expectation, five obsolete inactive-event expectations, and four repetitions
of a wrong classification of `genout/wpm_300_108_225@300:108:225` as an unrestricted
public NPC. Map300 has no general cave scope, but this second gate requires the
private original first-gate approach proof. The existing production policy is
correct. Classification now checks both scope and `action_approach`.

The king has no original quest branches and was omitted by branch enumeration.
The matrix now checks exact reviewed service identity, transmigration scope,
`transmigration_king` final-room mark, actual Backend preview rejection after
project arrival, unchanged profile, and inability to issue a SERVICE receipt.
This is a negative project-arrival test, not a substitute for the existing real
root/two-battle/last-gate positive integration suite.

Production events48–52 must be enabled;47 and53 remain excluded. A separate fresh
backend explicitly removes48–52 to retain the closed-catalogue lookup and exact
closed-service rejection for preview/confirm/cancel, with no profile mutation.
The old earth/fire/water source-fixture loops and baseline wind branches remain.

`quest_arrival_munde_wind_test` had one stale assertion combining public map100
with supposedly unprotected32021. The public return is still unrestricted;
32021 now correctly belongs to transmigration and requires the king mark. The
real Munde keyword/savefail/retry/seven-floor/final-battle checks are unchanged.

## Validation

Tests run sequentially, headless, without import/full/live operations, using
read-only current imported assets: world SHA256
`5bec114a4ee4571f08f2f4fd453ee1d40324ee876206ef3487d6e171b844d639` and catalogue
`c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92`.

- `/private/tmp/full194-arrival-case-matrix-fix.log`:0 failures,2167 branch/service rows.
- `/private/tmp/full194-arrival-munde-wind-fix.log`:0 failures, actual source route integration.

The original failure logs remain in the coordinator's full194 directory.
