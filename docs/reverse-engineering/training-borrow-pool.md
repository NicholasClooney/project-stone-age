# 借用高等级敌群练宠：候选池审计

这是默认开启的非原版助手便利。配置为 `client/data/training-borrow-pool.json`，只引用当前 catalog 的原版普通组，不加入自然遇敌、搜宠或捕获表。

## 选择与门控

选择 Lv80–105 同档内、原 area.max_enemies=10、素材完整的高经验普通组；四组实际等级90–105。未改等级、人数、成长或技能。每场按可用组均匀抽取，不套来源地区的组概率；组内仍沿原人数、槽权重、重复数量上限、大型最多5只、100次尝试和成长算法。

白名单排除任务、素材收集、事件、补充 rare/clone_of 组。运行时验证来源行号、enemy/template id、原等级、正组权重、真实优先级 area、可通行源格子、sprites及地面三种背景。requires/excludes item 按角色 original_items；event_now/event_end 正值或 enemy.condition 非空因核心未支持求值，一律排除。

“可访问”指当前游戏确已导入且支持进场的 field/training 地图、可通行源格子和组门控。map500与32016已作为开发练级地点导入（manifest dev_only）；借用不要求传送或购买旅行便利，不等于原版地理通路，也不冒充已完成任务。未导入或缺素材区域不可用。

## 原始来源逐项

以下全部是 `references/chenmingbiao-stone-age/gmsv/data/` 下对应原文件的一基行号。地图名来自当前 world manifest；catalog.provenance 保留四原表SHA256。导入器 `tools/import_encounters.py` 本次未改，未运行 importer。

| map_id / name | area_id / encount.txt / cell | group_id / group.txt | enemy.txt: id / name / Lv / line | enemybase.txt: template / line / sprite |
|---|---|---|---|---|
| 500 五十年前波拉岛 | 652 / :617 / [537, 500] | 767 / :643 | 1464 拉伊霍恩 Lv95-105 :1089<br>1463 卡伊霍恩 Lv95-105 :1088 | 314 :240 sprite100378<br>313 :239 sprite100377 |
| 500 五十年前波拉岛 | 659 / :623 / [218, 320] | 779 / :655 | 1491 加格 Lv90-95 :1113<br>1492 邦恩吉 Lv90-95 :1114<br>1490 加克拉 Lv90-95 :1112<br>1489 克邦凯斯 Lv90-95 :1111 | 223 :203 sprite100341<br>224 :204 sprite100342<br>222 :202 sprite100340<br>221 :201 sprite100339 |
| 500 五十年前波拉岛 | 659 / :623 / [218, 320] | 781 / :657 | 1486 拉可拉斯 Lv100-105 :1109<br>1485 萨美洛斯 Lv100-105 :1108<br>1484 史多拉奇顿 Lv100-105 :1107 | 325 :246 sprite100383<br>322 :243 sprite100380<br>321 :242 sprite100379 |
| 32016 漆黑的洞窟 地下16楼 | 626 / :591 / [29, 29] | 753 / :630 | 1394 邦浦洛斯 Lv93-95 :1026<br>1396 拉可拉斯 Lv93-95 :1028<br>1398 布林帖斯 Lv93-95 :1030 | 93 :93 sprite100289<br>325 :246 sprite100383<br>252 :214 sprite100352 |

四个area原人数上限10。779的4种小型宠各max_count=3；767的2种大型各10；781的3种大型各3；753的3种大型各5。原tactics保留在catalog，目前沿已支持的原战斗行为，不虚构特殊技能。

## 背景与音乐

源地图资产为 `client/assets/legacy/world/500.map` 与 `32016.map`。源格子真实ground bitmap：652为564，659为885，626为1219。按原battlefields.json映射到ground及三种field，独立池流选一种，snapshot携带原texture路径。UI与无backend remote只读该元数据，手动接管沿用；缺源背景则该组不可用，不换造背景。

500源环境音乐为 `world/audio/sabgm_f0.wav`；32016无独立环境音乐。source_music保留作审计，战斗继续原battle_art音乐，战后恢复当前所在地音乐/电台，不播放远地图环境音乐或搬动玩家。

## 经验、触发与保护

复用TrainingTroops真实上下文。只有实际训练的出战/受保护宠物借用，坐骑/角色fallback不借。每场计算实际目标（cap120）剩余XP，严格 `remaining_xp > 5*local_best_expected` 才借，=5本地。当地最佳为0且仍有剩余时按无限场处理；无可用池明确暂停。与select_troops独立：关挑群仍可借，关借用则按挑群开关使用当地，双方关闭原遇敌。

真实solo/squad/LAN Battle core与训练policy预测五次，第一场必须赢且五次至少四赢；单场最多200回合，按1000μs预算逐回合续算。目标uid/目标等级、clone/骑宠、完整成员配置、设置、原地位置与实际battle seed必须一致，否则暂停。LAN成员自动策略取实际角色设置并在进场前复核；手动成员的未来动作无法预知，预测沿原超时普通攻击作为基准，实际手动指令仍由成员掌握，不承诺预测必胜。弱队预测不能胜明确暂停，无伪胜；保护、停机线、精灵及LAN共享/未共享限制保持。

EXP和石币走原settlement，倍率一次，坐骑/LAN gap原处处理，BATTLEGOLD按开战前角色level×10一次，重复battle_id拒绝。原drop白名单只有审计过利润/退出路径的enemy563；池不含563，因此虽然原表部分ITEM/ITEMPROB非空，仍生成空drops，不新开刷物品入口。以后启用仍需沿generated_drops/claimed/save机制单独审计。

## 独立流、保存与恢复

Backend.training_pool_rng消费均匀group draw、完整组roll和源背景选择。walking/pressure/hunt_run_seed/C helper流不动。完整池roll后先将decimal-string seed/state写入角色可选v6字段training_borrow_rng并成功保存，再预测/开战；写失败暂停。resume也记录该字段，优先角色最新状态，不用旧resume回滚。预测/中断消耗的roll不重用，重启从下一roll继续；未完成战斗无收益，已结算由原completed_battles防重。旧v6无此字段时独立随机初始化，不加SaveVersion。

## 实测场数

真实catalog/Backend/Battle/Session，原宠Lv1→120，角色Lv120且GM strength/toughness=500，10×XP，保护开启：seed0..9总场数为 `4,2,3,3,2,2,4,4,3,4`，中位数3，范围2–4；这些seed都直接跨过尾端，无本地场。所有奖励均真实胜利结算，没有hard-coded awards，未把2场伪报3场。

不能保证每seed或弱队3–5场：原人数/大型上限、LAN gap、倍率、剩余尾端与战力改变收益；回本地尾段可能加场。四组有意选择原同档较高经验且max10的普通组，未篡改等级/人数。逐seed证据在training_borrow_test的MEASURE日志。
