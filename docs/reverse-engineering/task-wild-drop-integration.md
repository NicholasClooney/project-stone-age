# 任务专用野战掉落 A：服务器结算接入

用户于 `main c298d39` 正式选择 A。本保护是**项目补充**，不宣称原 C 会检查项目瞬移。没有合法到达资格仍能战斗、抓宠、获取普通经验和金币，只扣留精确审核来源的专用掉落。

## 源与依赖

- 位置权威基线：`c55fd28548589f2a0e40d91cff98683f99c0e5ad`。
- arrival 原始策略/API：`6af90df20c57195677e6ba590514addab1ba78af`，本槽等价 `a62d781`。`client/data/quest-wild-drop-policy.json` 的214条规则逐项包含 scope/map/area/group/enemy/item/原slot 与物理源行，Python oracle 按锁定 SHA 重建原 E/G/A 图。
- 本槽仅供验证的依赖整合 `12e181b`：见 [依赖清单](wild-drop-local-dependencies.md)。主线取原政策序列时不要重复取此快照或本槽等价提交。
- `30305` 深蓝石已由 arrival owner 给出 `883bf9b` 与真实门 `188f648/0bb3ccf` 双入口证据，纳 `water_stone`；`1099` 木材仍无完整原入口证据，排除。公开200木材实际group414也排除。
- 本接入不更改任务manifest/importer，也不重新启用任务。未导入的地/水来源要随各链已有导入流程启用；不能把214条静态规则存在当作全部任务已开放。

## 运行接点

1. `EncounterCatalog.actor/roll_drops` 在原来那一次抽取成功时，平行写入 `generated_drop_slots`。使用导入器 `drop.slot`，即原enemy.txt十槽零基位置；不是稀疏 `enemy.drops` 序号，更不是中奖列表下标。不增加或删除任何RNG调用，不改变候选claims的生成和数量上限。
2. `Backend.open_battle` 在party hook之前调用独立 `QuestWildLoot.freeze`。来源来自服务器pending的原area/group/enemy及真实地图；保护键是完整源元组。只存在于内存的pending持有规则与 `wild_context`；外部命令不能提交或替换此上下文。
3. `PartyBattles.open` 在各成员pending创建后，仅复制可信leader源元组，再分别调用各自arrival实例的 `wild_context`。不复制leader资格、epoch、结算slice或claims。自然队列尾随成员可以有不同cell；借用敌群则还要求本人实际在其原源map/cell，不能仅凭同scope借取另一点的任务物品。
4. `_after_turn` 先冻结原个人／party结果，验证**完整原claims**的索引、重复、死亡与未捕获条件。任何不合法条目仍原样交Session拒绝，不能被过滤消失。仅对合法claims的候选副本，按开战冻结的完整来源规则和最终 `check_wild` 过滤。Session原验证未放宽；claim.item始终是中奖列表索引，物品ID只从可信开战记录读取。
5. 无到达资格只产生 `quest_drop_denied` 与中文项目补充说明；照常结算HP、药耗、宠物、XP、金币和其它slot，可正常close。新增掉落保护沿现原子保存事务；save失败恢复profile、capture_events、完整pending，重试不重抽、不消费或刷新旧epoch。未知／缺失／重复／错物品的来源槽位属于内部来源校验失败，不能当作普通不受限制掉落。
6. `GameSession.apply_battle_result` 只在捕获转换的临时字段erase名单追加 `generated_drop_slots`，不改保存schema或物品仓库逻辑。

固定守卫原有专用物品策略仍独立处理；本片不改变固定NPC组队战禁令。UI背景任务、disconnect/reconnect、仓库命令及六旧链helper/auto由其它owner维护，本片不触这些区域。

## 定向证据

新增注册七套：`wild_task_drop_slots_test`、`wild_task_drop_test`、`wild_task_drop_party_test`、`wild_task_drop_hunt_test`、`wild_task_drop_remote_test`、`wild_task_drop_auto_test`、`wild_drop_capture_metadata_test`。

- 真矿石原seed27，通过300原入口及1F逐格到可走(37,48)，对照孤立项目到达。wild/field_step/stationary各合法与非法六组合；真战、保存失败两次重试、普通金币/完成记录、幂等close、离开／返回和reset失效。
- 真Hub两角色实际原portal与队列步，各自冻结来源。真实成员击杀；分别令队长或击杀者失格，个人savefail保留slice/claims，非法索引和重复原claims仍被Session拒绝，队员正常close。
- 慢搜和真实native executable均寻找混矿敌群，随后真实战斗；native排队候选经原服务器replay、实际 `_showcase_capture` 开战，均不借搜宠目标获得任务资格。
- 真双WebSocket：角色合法入洞开战，终战保存失败；第二设备项目命令按现忙碌规则拒绝。其旧式跨格report可变更位置但撤资格，伪client/arrival_kind无效；回原格不能续旧epoch，第一设备重试只结算普通战果。
- 正常自动练级启停，合法得矿石／非法抑制；真实捕获、save/read-back保原species/name/level/growth/ID/战斗属性，均不含临时掉落数组。
- 原slot稀疏/零概率/RNG对照，未知slot/错ID失败，借敌群同scope不同map或同map不同cell不能借资格。实际原enemy1334同次抽得1249（slot0）与2766（slot1），过滤只扣留2766，原中奖记录不变。该单元路径验证精确源与候选claims，不把未导入1249的本槽称作水链完整物品入包验收。214源规则另由owner套件及Python oracle覆盖，不能把矿石运行矩阵称作每条链均已逐一完成UI路线。

本片为headless服务器行为验证，没有新增像素验收；无full。外部详细日志及最终hash由交接文件列出，测试失败的早期日志保留供追溯。

## 部署

本接入无需重新导入美术或修改原数据；须合齐原arrival政策/API与各任务已审核的现有导入片。正常重建生产主PCK，确保 `res://data/quest-wild-drop-policy.json` 和新server脚本进入包；仅替换地图pack不足。服务器重启自然清除内存到达记录，不迁移真实save。
