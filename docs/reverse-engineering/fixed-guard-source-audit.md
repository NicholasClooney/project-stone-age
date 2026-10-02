# Fixed guard source tactics and skill audit

Runtime remains the existing combat AI. The source tactics and seven enemybase skill slots below are audit metadata; this change does not restore the original special skills. Legacy A NPC ids remain unchanged.

| NPC | Enemy / source row | Tactics | Original slots (enemybase row; petskill source rows) |
|---|---|---|---|
| 300/sb_5b1.arg | 1001 / enemy.txt:641 | at:3;1;1\|gu:1\|es:0\|wa:0;0;1;1;0;0;0; | enemybase.txt:367; 0:1 攻击 PETSKILL_NormalAttack  (petskill:2); 1:2 防御 PETSKILL_NormalGuard  (petskill:3); 2:30 突击 PETSKILL_ChargeAttack 1 攻%+90 (petskill:10); 3:31 双重突击 PETSKILL_ChargeAttack 2 攻%+110 (petskill:11); 4:(empty) 待机 PETSKILL_None  (petskill:1); 5:(empty) 待机 PETSKILL_None  (petskill:1); 6:(empty) 待机 PETSKILL_None  (petskill:1) |
| 300/sb_5b2.arg | 1012 / enemy.txt:651 | at:1;1;1\|gu:1\|es:0\|wa:0;0;1;1;1;0;0; | enemybase.txt:368; 0:1 攻击 PETSKILL_NormalAttack  (petskill:2); 1:2 防御 PETSKILL_NormalGuard  (petskill:3); 2:50 背水之战其之１ PETSKILL_PowerBalance 攻%+25 防%-35 (petskill:14); 3:51 背水之战其之２ PETSKILL_PowerBalance 攻%+45 防%-55 (petskill:15); 4:52 T背水之战之其３ PETSKILL_PowerBalance 攻%+80 防%-50 (petskill:16); 5:(empty) 待机 PETSKILL_None  (petskill:1); 6:(empty) 待机 PETSKILL_None  (petskill:1) |
| 300/sb_5b3.arg | 1013 / enemy.txt:652 | at:1;1;1\|gu:1\|es:0\|wa:0;0;1;1;0;0;0; | enemybase.txt:369; 0:1 攻击 PETSKILL_NormalAttack  (petskill:2); 1:2 防御 PETSKILL_NormalGuard  (petskill:3); 2:60 毒攻击 PETSKILL_StatusChange 毒 turn 3  攻%-30 (petskill:17); 3:61 猛毒攻击 PETSKILL_StatusChange 毒 turn 5  攻%-50 (petskill:18); 4:(empty) 待机 PETSKILL_None  (petskill:1); 5:(empty) 待机 PETSKILL_None  (petskill:1); 6:(empty) 待机 PETSKILL_None  (petskill:1) |
| 300/sb_5b4.arg | 1014 / enemy.txt:653 | at:1;1;1\|gu:1\|es:0\|wa:0;0;1;1;0;0;0; | enemybase.txt:370; 0:1 攻击 PETSKILL_NormalAttack  (petskill:2); 1:2 防御 PETSKILL_NormalGuard  (petskill:3); 2:40 一击必杀 PETSKILL_Mighty 倍2 回避30 (petskill:12); 3:41 T一击必杀改 PETSKILL_Mighty 倍3 回避15 (petskill:13); 4:(empty) 待机 PETSKILL_None  (petskill:1); 5:(empty) 待机 PETSKILL_None  (petskill:1); 6:(empty) 待机 PETSKILL_None  (petskill:1) |
| 300/sb_5b5.arg | 1015 / enemy.txt:654 | at:3;1;1\|gu:1\|es:0\|wa:0;0;1;0;0;0;0; | enemybase.txt:371; 0:1 攻击 PETSKILL_NormalAttack  (petskill:2); 1:2 防御 PETSKILL_NormalGuard  (petskill:3); 2:110 催眠攻击 PETSKILL_StatusChange 眠 turn 3  攻%-30 (petskill:22); 3:(empty) 待机 PETSKILL_None  (petskill:1); 4:(empty) 待机 PETSKILL_None  (petskill:1); 5:(empty) 待机 PETSKILL_None  (petskill:1); 6:(empty) 待机 PETSKILL_None  (petskill:1) |

The same structured `combat_audit` is generated for reviewed module NPCEnemy
branches from SHA-pinned enemy.txt/enemybase.txt. It stores raw rows, original
tactics, skill ids/names/functions/arguments, all seven slots, and petskill.txt
SHA256/source lines. Optional task `combat_audit:{path,sha256}` is retained as
`review_document` attribution; it is not substituted for the directly parsed
source records. Task agents maintain their route-specific written enemy tables.

Munde: 527,526,528,529 in that order; Jan: 961,963,962 in that order.
Their exact rows and seven slots are in the source-bound regression fixture
`client/tests/fixtures/original-fixed-guards.json`.
