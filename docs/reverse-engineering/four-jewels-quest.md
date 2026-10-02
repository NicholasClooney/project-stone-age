# 四宝玉实际绑定与敌源审计

本报告依据本地锁定C快照，恢复实际绑定的四宝玉任务45。公共个人NpcWarp与经源槽校验的随机掉落已接入。

## 实际任务与条件遭遇

实际学者为 `extra/event/hougyoku.create:8–18` 的6000(58,44)，只绑定 `extra/event/hougyoku`。
旧 `giiru/event/sink/equiz_04` 未绑定，不能以猜谜箱替代END45。

原请求最低60级给予2764结晶石；交付要求60级、2764及2760/2761/2762/2763各一，
收五物、给2765、END45。原NpcWarp目标依次4000(53,101)、2000(44,39)、
5105(14,3)、6000(58,44)。按用户B裁定为每角色服务器内存位置，成功保存后移动，重启复位。

条件组 `group.txt:588–591` 为711/712/713/714：都要求2764；分别在持有
地2760/水2761/风2763/火2762时排除对应组。不是任务旗标强行刷怪，也不是四精灵或英雄岛四圣石。

| 来源行 | 原区域 / 组 | 原组权重 |
|---|---|---|
| encount.txt:34 | 100 (621,341)–(645,412) / 711地 | 4，相邻普通组6/6 |
| encount.txt:90 | 200 (91,564)–(250,671) / 712水 | 1，相邻普通组9 |
| encount.txt:288 | 300 (85,37)–(233,195) / 714火 | 10，其余15/15/15/20/20/1 |
| encount.txt:355 | 400 (0,0)–(149,148) / 713风 | 12，其余10/10/10/10/10/2/1/65 |

实际命中还必须使用原区域优先级；区域几何相交不保证该位置最终选择这行。

## 掉落与奖励边界

原敌1305地/1306水/1307风/1308火各自唯一宝珠槽，概率为100/500/500/100，
分母1000（不是百分百）。不得通过网页或显示名称调换风/火ID。掉落需走真实战斗结算、
个人归属、失败保存可重试且不能重复结算。

月光的手镯2765源itemset.txt:2276：普通攻+3、防+3、敏−3、魅+1，60级；
魔法55/56/57列为300/0/35（复活守护Lv1），仅标签且未生效。
原描述漏掉魅+1，取数值列，不扩大效果系统。

源SHA及原行固定在 `tools/four_jewels_quest_sources.json`；未导入任何未绑定副本。

## 每个条件组敌人的原战术、技能和异常来源

原AI本批不恢复，继续现有战斗AI。以下保留所有13个原敌行，含随从；
`wa`为七技能槽权重，`at/gu/es`保持原字符串。原技能列为enemybase零基25–31，
异常耐性为19–24。不将原战术标为已实现。异常技能函数/参数同样保留，不新增状态系统。

| enemy line / ID / template | tactics | enemybase line / skill slots | resistance columns |
|---|---|---|---|
| 937 / 1305 / 678 | `at:1;1;1|gu:1|es:0|wa:1;1;0;0;0;0;0;` | 479 / `30,41,,,,,` | `100,100,100,100,100,100` |
| 938 / 1306 / 679 | `at:1;1;1|gu:1|es:0|wa:1;1;1;1;1;1;1;` | 480 / `60,61,80,90,100,110,52` | `100,100,100,100,100,100` |
| 939 / 1307 / 680 | `at:1;1;1|gu:1|es:0|wa:1;1;1;1;1;0;0;` | 481 / `152,13,12,10,11,,` | `100,100,100,100,100,100` |
| 940 / 1308 / 681 | `at:1;1;1|gu:1|es:0|wa:1;1;0;0;0;0;0;` | 482 / `30,31,,,,,` | `100,100,100,100,100,100` |
| 941 / 1309 / 1 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 1 / `1,,,,,,` | `0,0,0,0,0,0` |
| 942 / 1310 / 3 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 3 / `1,20,,,,,` | `0,0,0,0,0,0` |
| 943 / 1311 / 221 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 201 / `1,,,,,,` | `0,0,0,0,0,0` |
| 944 / 1312 / 263 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 222 / `1,2,,,,,` | `0,0,0,0,0,0` |
| 945 / 1313 / 264 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 223 / `1,2,,,,,` | `0,0,0,0,0,0` |
| 946 / 1314 / 291 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 229 / `1,,,,,,` | `0,0,0,0,0,0` |
| 947 / 1315 / 292 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 230 / `1,120,,,,,` | `0,0,0,0,0,0` |
| 948 / 1316 / 293 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 231 / `1,,,,,,` | `0,0,0,0,0,0` |
| 949 / 1317 / 294 | `at:1;1;1|gu:0|es:0|wa:0;0;0;0;0;0;0;` | 232 / `1,,,,,,` | `0,0,0,0,0,0` |

| ID / petskill.txt line | name | original function / argument |
|---|---|---|
| 1 / 2 | 攻击 | `PETSKILL_NormalAttack` / `` |
| 2 / 3 | 防御 | `PETSKILL_NormalGuard` / `` |
| 10 / 5 | 连续攻击 | `PETSKILL_ContinuationAttack` / `2` |
| 11 / 6 | 三段攻击 | `PETSKILL_ContinuationAttack` / `3` |
| 12 / 7 | T四段攻击 | `PETSKILL_ContinuationAttack` / `4` |
| 13 / 8 | T五段攻击 | `PETSKILL_ContinuationAttack` / `5` |
| 20 / 9 | 忠犬 | `PETSKILL_Guardian` / `攻%-20  COM:攻击` |
| 30 / 10 | 突击 | `PETSKILL_ChargeAttack` / `1 攻%+90` |
| 31 / 11 | 双重突击 | `PETSKILL_ChargeAttack` / `2 攻%+110` |
| 41 / 13 | T一击必杀改 | `PETSKILL_Mighty` / `倍3 回避15` |
| 52 / 16 | T背水之战之其３ | `PETSKILL_PowerBalance` / `攻%+80 防%-50` |
| 60 / 17 | 毒攻击 | `PETSKILL_StatusChange` / `毒 turn 3  攻%-30` |
| 61 / 18 | 猛毒攻击 | `PETSKILL_StatusChange` / `毒 turn 5  攻%-50` |
| 80 / 19 | 石化攻击 | `PETSKILL_StatusChange` / `石 turn 3  攻%-30` |
| 90 / 20 | 混乱攻击 | `PETSKILL_StatusChange` / `乱 turn 3 攻%-30` |
| 100 / 21 | 泥醉攻击 | `PETSKILL_StatusChange` / `醉 turn 3 攻%-30` |
| 110 / 22 | 催眠攻击 | `PETSKILL_StatusChange` / `眠 turn 3  攻%-30` |
| 120 / 23 | 地球一周 | `PETSKILL_EarthRound` / `攻%+90` |
| 152 / 28 | T不防守战法3 | `PETSKILL_NoGuard` / `回避%+50 反击%+70 会心%+40` |


## 验收与复现

`four_jewels_quest_test` 使用实际条件遭遇RNG、原敌、真实战斗胜利和原掉落结算，
覆盖四珠、无结晶石排除、已有宝珠排除、掉落保存失败保留原roll重试、重复关闭防重领，
以及五物交付保存失败原子回滚、奖励与END45、个人NpcWarp、重启复位、双socket同角色一致性与不同角色隔离。
没有直接给测试角色四珠，也没有修改敌人掉落概率。测试用GM等级和属性提高胜率，并选定合法RNG种子，
不以此证明自然等待时间或原AI已实现。全部13个条件组敌源的原AI/技能见上表，仍使用当前AI。

`four_jewels_equipment_test` 验证手环59级拒戴/60级可戴、实际攻防敏魅、原无异常抗性、
真实受击耐久消耗、UID及耐久存档；复活守护魔法只标签且未生效。助手导出的普通属性标志为active，
魔法标志为inactive，原itemset描述缺魅+1不覆盖数值列。

`four_jewels_ui_test` 已在390×844真实OpenGL渲染运行并真实点击：请求、四个原条件遭遇区域、
四场原敌战斗的攻击/目标/返回、五物交付、奖励滚动详情、装备及移动后学者对话。
10图逐张人工查看，存于本机 `/private/tmp/bonus-third-jewels-proof`，不提交截图。
手机用GM60级和四项500属性、选合法单敌掉珠RNG；战斗与掉落由真实服务端结算。
没有运行full。

```sh
PYTHONPATH=tools .tools/asset-venv/bin/python -m unittest tools/test_four_jewels_quest.py
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
STONE_AGE_TEST_JOBS=2 ./scripts/test-all.sh --only four_jewels_equipment_test,four_jewels_quest_test
STONE_AGE_FOREGROUND_TEST=1 STONE_AGE_PROOF_DIR=/private/tmp/bonus-third-jewels-proof ./scripts/run.sh --rendering-method gl_compatibility --script res://tests/four_jewels_ui_test.gd
```
