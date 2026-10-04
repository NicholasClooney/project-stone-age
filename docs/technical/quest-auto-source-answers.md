# Source answers for automatic quest proposals

This is an isolated lookup module, not an enabled automatic quest. It does not register job2/event44, call a service, move a character, buy tickets or control random outcomes. Manual questions and original keyword services are unchanged. The runner and service-action contract must be integrated separately before these proposals can execute.

## Input and output

Instantiate `res://server/quest_auto_source_answers.gd` and call:

- `resolve_quiz(source: String, dialogue: Dictionary)` for one of the21 reviewed original quiz service IDs.
- `resolve_keyword(source: String, dialogue: Dictionary)` for one of four reviewed original gate source IDs.

Both accept only a source key supplied by an audited caller and an original **public** dialogue. Success is `{status:"answer", choice:String, text?:String, evidence:Dictionary}`; failure is `{status:"manual", reason:String}`. Evidence includes source path/SHA and table SHA; quiz evidence also includes original question IDs and question-file SHA. Do not publish the evidence as a player capability. The output carries no token, run identity, coordinates or actions. A future runner must bind its own current service token and run/step/revision, recheck authority, then use the original transaction.

The module has no backend, original-service instance or RNG input. It never reads `pending.service_state`, `answer_choice`, `answer_text`, order or an opponent hand. Public token/name fields may be present but are not used or returned. It does not infer eligibility from a client-supplied source key; actual admission remains the runner/service's responsibility.

## Original scope

The source revision is `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`. The generator independently pins28 source-file hashes: question.txt, npc_quiz.c, quizman.create,21 challenge scripts and four keyword scripts. It reads only those reference files and writes only its owned static JSON. No existing asset importer or shared assets are modified.

The149 valid question records retain their original IDs, source lines, text, options, type, level mask and answer index. Original question8 has only eight comma fields and remains excluded according to npc_quiz.c:957–994. The forms are22 two-choice,84 three-choice and43 text-answer questions. The21 quiz services are the seven reviewed question floors in each800/820/840 chain; service-specific type/level/answer masks select the original question pools. Level masks are not character levels. Unopened812/END47 is absent.

The four keyword sources are:

| Source | Original submitted text |
| --- | --- |
| `genout/wpm_100_443_127` | 在卡坦有梦德 |
| `genout/wpm_20604_11_53` | 红色月亮的光芒 |
| `genout/wpm_20605_51_4` | 蓝色山脉即力量 |
| `genout/wpm_20606_9_23` | 白色之风即速度 |

Fire water amounts and the five-brothers answer-NPC mapping are not included. This module cannot choose a reward tier, pet UID, Boss action or ticket purchase.

## Matching and failure behavior

Quiz lookup validates the exact source NPC, public kind, input form, anchored question-group header and complete choice-ID shape. It compares the current option **multiset** against the original options before mapping the correct source text to the current shuffled ID. It never treats the source answer index as a current button ID. Unknown questions, changed distractors, missing/extra options, duplicate IDs and ambiguous correct choices remain manual.

Exact text is tried first. A fallback converts fullwidth ASCII U+FF01–FF5E, fullwidth space U+3000 and CRLF only for lookup; it does not trim, collapse spaces, case-fold, delete punctuation or rewrite names. Every matching candidate must agree on one output. Original duplicate question IDs1/22 and10/47 agree and retain both evidence IDs. Width collisions or conflicting source candidates remain manual. The current original choice text may contain trailing spaces; they remain part of the compared multiset.

Text answers return the original first option byte-for-byte as a Godot string, including spaces and width. The original service uses substring matching, but the module never concatenates candidate answers or guesses extra strings. The future service still decides whether a submission is correct.

The JSON's complete serialized SHA256 is pinned in the runtime module. Missing data or any changed content, including a changed source SHA, makes both public lookup methods return manual. Updating source content requires a reviewed generator/pin change and matching runtime digest, not a silent fallback to a service's private catalog.

## Reproduction and validation

```sh
python3 tools/build_quest_auto_source_answers.py --check
python3 tools/test_quest_auto_source_answers.py
./scripts/run.sh --headless --script res://tests/quest_auto_source_answers_test.gd
```

To rebuild after an explicitly reviewed source change, omit `--check`, review the owned JSON diff, and update its runtime digest. The generator has no arbitrary output-path option. Source SHA drift fails before generation. Tests compare deterministic output and runtime digest, original raw fields, excluded malformed row, all service pools and four keywords, and mutate a temporary copy of a reference to prove hash rejection.

The pure Godot suite enumerates all591 choice permutations across149 questions, repeats width-normalized public presentations, checks every declared service's eligible pool, and covers malformed/unknown/ambiguous inputs and modified-table rejection. It constructs public dialogue fixtures only; no private service state, grants or winning seeds are used. These are lookup tests, not a claim that actual tickets, ten-floor traversal, original random janken retries or map-ready acknowledgements have been integrated.
