# Original quest item predicates

Pinned source: `references/chenmingbiao-stone-age/gmsv/npc/npc_exchangeman.c`.

- `NPC_EventBigSmallCheck:709–725` handles `!=` before the quantified `=`
  branch. `ITEM!=id*n` consequently ignores the quantity and checks absence of
  that ID, just like `ITEM!=id`.
- `NPC_EventFreeIfCheck:751–755` dispatches ordinary ITEM checks to
  `NPC_EventItemCheck:1045–1070`. Its explicit comment and loop at 1051–1052
  exclude equipped slots, starting at `CHAR_STARTITEMARRAY`. Plain `ITEM=id`
  requires a bag copy; `ITEM!=id` is true when all copies are worn or absent.
- Quantified `ITEM=id*n` calls `NPC_EventReduce:3671–3708`. It starts at slot
  zero, includes worn items, counts original stack quantities, and succeeds at
  `count >= n`. This project's reviewed task items are non-stacking instances.
- Deletion is a separate action. `NPC_EventDelItem:3257–3369` scans from slot
  zero for unquantified deletion; quantified deletion has an empty ordinary
  branch at 3281–3282. The existing documented compatibility correction remains:
  `DelItem:id*n` deletes exactly n copies, worn-first; unquantified deletion
  removes all copies. This change does not restore that empty-source bug.

The common matcher now follows the distinction without changing any equipment
schema, item definitions or save version. It reads equipped UIDs without mutating
the profile. The common helper cache includes equipment location, and its
blocked-step explanation asks the player to unequip a required item when only
the worn copy exists.

Visible impact on already delivered quests: Barl's plain `ITEM=2465` no longer
accepts a worn-only Hahn axe. Unequip it before handing it back. Item conditions
elsewhere follow the same source rule; non-wearable herb/flower/paper/mirror
items remain unaffected. Quantified adult-jade and other quantity checks still
count all owned copies. New Yam axe content uses this common rule rather than
an item-specific exception.

`original_quest_item_predicates_test` uses the actual Barl source branch and real
Backend equip/unequip commands. It checks worn-only and duplicate-copy positive,
negative and quantified conditions, helper cache refresh, save rollback, actual
completion and unchanged worn-first quantified deletion. Existing wood, herb,
doctor and brothers suites provide regression coverage.
