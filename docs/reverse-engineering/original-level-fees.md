# Reviewed original level-based fees

The shared importer and transaction service accept only non-negative decimal
constants up to 2147483647, `LV*20`, and `LV*40`. This does not activate the quiz
route or change its admission predicates. Other expressions fail closed.

Source: `references/chenmingbiao-stone-age/gmsv/npc/npc_exchangeman.c:3960–3974`
(`NPC_EventGetCost`) reads the current character level and multiplies it by the
integer following `*` when the argument contains `LV`; otherwise it calls
`atoi`. The project deliberately supports only the reviewed exact expressions,
not the C parser's permissive substring/atoi behavior. Negative values and
signed-int overflow are rejected before any mutation.

The exact source fixture `client/tests/fixtures/original-level-fees.json` retains
source hashes, original messages and predicates, itemset rows, and all four
actual create instances from `gmsv/data/npc/quiz/quiz.create`:

- `quiz/uketuke`, branch 1: `LV>49`, `LV*40`, item 2756.
- `quiz/uketuke`, branch 2: `LV>29`, `LV*20`, item 2755.
- `quiz/uketuke2`, branch 0: `LV>69`, `LV*40`, item 2757.

The earlier refusal branches remain in the fixture, so admission still uses
first matching source branch. The `%8d` fee placeholder displays the server's
current calculation. Both helper availability and the final transaction use
`OriginalQuests.stone_cost(profile, expression)`. Final confirmation rechecks
the source branch, current level and current funds. Only the saved candidate
receives the ticket and deduction; failed save rolls back both, and consumed
tokens cannot issue a second ticket.

Validation covers real Backend/Session original A/B/C sales, level and balance
changes after the opening dialogue, exact balance, save failure, replay, and
signed-int boundaries. The existing two-device LAN transaction checks remain
in the same targeted suite. Fixture import tests compare source hashes and
original action strings. No full suite was run for this slice.
