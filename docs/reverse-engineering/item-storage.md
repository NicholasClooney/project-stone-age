# 每角色物品仓库：源规则与项目改动

2026-10-03。实现基线为独立 `main` 的 `c298d39`；未依赖未合入四链包或第三阶段转生。原版容量、禁存与费用锁源；用户最终决定覆盖容量、堆叠与费用。

## 已选范围与估算

道具窗口的「物品仓库」按钮直接打开，仓库中「背包 · 存入」「仓库 · 取出」支持单选、多选和堆内数量。每角色 **3000格**，免费存入、免费取出；界面与日志标为「项目改动」。原来需要访问NPC；不开放转生、不改背包堆叠、不添加NPC或任务奖励。

增量估算 **2–3.5 SP**，以已完成Samgir=1、村民对话=0.5校准。复用持久化、原实例UID、库存与LAN底座，不再次计基础系统；增量包含源规则审计、跨容器校验、整批事务、双尺寸入口/多选/拆堆、真实最大容量LAN和保存失败验证。相较初始1.5–2.5 SP，新增加3000格与64堆的边界、最大192000 UID网络成本；不是时间换算。

## 原源码证据

来源 `references/chenmingbiao-stone-age/`：仓库处理器是 `gmsv/npc/npc_poolitemshop.c` 的 `NPC_PoolItemShop`，不是普通商店 `npc_itemshop.c` 的 `NPC_ItemShop`。

- `gmsv/char/char_base.c:1426–1427,1443–1444`：`min(10 + 4 * CHAR_TRANSMIGRATION, CHAR_MAXPOOLITEMHAVE)`。
- `gmsv/include/version.h:120` 开启 `_ADD_POOL_ITEM`；`char_base.h:281–285` 因而上限30，未启用分支上限20。当前 `player.transmigration` 已有严格整数校验；`ItemStorage.original_capacity(profile)` 保留原计算，**没有启用**。`capacity()` 固定3000；转数变化不降低本期容量。
- `npc_poolitemshop.c:701–711` 从 `CHAR_STARTITEMARRAY` 扫随身背包，给 `ITEM_DROPATLOGOUT || ITEM_VANISHATDROP || !ITEM_CANPETMAIL` 标不可寄存。其共享仓库写入入口 `NPC_DepotItem_InsertItem:470–477` 也检查三标记；普通 `NPC_PoolItemShop_PoolItem:760` 本身缺重复校验，本项目在权威端完整校验，不信任客户端禁用按钮。
- `gmsv/item/item.c:385–388` 的三标记对应 `itemset.txt` **零基列78、79、81**（列80是isovered，不是canpetmail）。直接读取已导入、锁源的 `raw_columns`；缺证据的物品拒绝寄存。
- `npc_poolitemshop.c:10,85–87` 缺省费用200；`gmsv/data/npc/genout/pis_1009_14_13`、`pis_2009_17_34`、`pis_3009_18_40`、`pis_4009_15_13` 首行均为 `cost:50`，其他四个pis文件同值。`:763–788` 每真实存入件扣NPC费用，取出不扣费。本期用户选 **A：两向免费**，没有保留收费切换或接收客户端价格的产品分支。

允许/禁止不是“任务物品”类别判断：

| 物品 | 原标记及结果 |
| --- | --- |
| 月光花2424、勾玉2421、良质木材2468、萨顿家的秘药2450、入场券2755–2757 | 78=0、79=0、81=1，允许存；因此某些任务物品确实可存 |
| 空想的帽子2605等已核奖励装备 | 三标记允许；须先卸下，每件独立占格 |
| 哈罗香草2401、交付斧2416、心性之镜2547、真实之眼2548、水壶2708 | 79=1、81=0，禁止存 |
| 答案纸2507等临时物 | 78=1，且79=1、81=0，禁止存 |
| 无原列证据或项目恢复宠物辅助道具healing_charm | 明确显示暂不支持，不推测原映射 |

旧计数物品仅映射已核的药1500、棍100、镜1460、铠1011、服1112/1113、护符1450，原三标记都允许。它们保留既有计数模型：药在仓库显示64上限的堆，旧装备每件一格；取回仍用背包原计数与99上限。旧模型本来没有UID或耐久，不伪造UID，也不与同模板原实例混合。

SHA256：

| 源文件 | SHA256 |
| --- | --- |
| itemset.txt | `c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d` |
| npc_poolitemshop.c | `67978326b8c08afaa2effa7934bd3461456d89697bf614c13d690709eca396aa` |
| char_base.c | `0fb9501a891989799a4e6d6b407f14bdf2dfbe903df8169ff64d57a67826b287` |
| char_base.h | `167e0ef3dfc758fd407942110ac4eb3292d94c7f31b6a87fcd3eff98b657a770` |
| version.h | `081d634dd5c9f87ff6ce28952c96a2e110b51158daadd52dad15a32972da7d94` |

## 存档、UID与事务

`SAVE_VERSION`仍为6，增加一组可选字段：

```text
item_storage: [{uid, item_id, durability}, ...]
legacy_item_storage: {legacy_key: positive_count, ...}
item_storage_revision: monotonically increasing integer
```

旧存档三个字段都没有时，读取快照补空仓与revision=0；半缺、非法类型/整数、非法耐久、禁存物、超过3000格、同UID跨背包仓库重复或UID不小于next_original_uid均拒绝。沿既有load/save原子替换与备份路径读回；不访问真实存档。无UID销毁/重新分配，next_original_uid原样保留。当前实例schema严格为既有三个字段，未知绑定/独特属性字段不会被吞掉：旧schema会拒绝，未来支持该属性需先做明确迁移。

原实例仓库只对 **原类型16(OTHER)/20(DISH)、零耐久、无额外个体字段、原标记可存** 的同模板物品分组，每组最多64。UID仅是身份，不当作阻止分组的独特属性。装备类型0–15/17–19与其他未知类型始终独立；有耐久也独立。底层保留每件字典，显示堆的成员依仓库顺序确定；拆取发送选中组前N个确切UID，回背包后恢复每件独立占格。不存在真实绑定UID语义的已支持可聚合实例；未来不能因同模板直接合并绑定/随机属性实例。

RPC `item_storage_transfer` 要求 `direction=deposit|withdraw`、`revision`、`items`。原实例存入选择器 `{uid}`，取出 `{uids:[...]}`；旧计数选择器 `{key,count,offset}`。服务器从当前所有权、组边界与数量重建合法选择器，拒绝重复、非法、缺失或旧修订号。任何设备成功后revision加1，即使物品又取回，也不能重放旧存入请求。

先完成所有权/去重/可存/已穿戴/容量/背包15格校验，构造候选profile，再保存；失败恢复整个before且不发布，成功只发布一次普通profile事件。对战斗open/pending/party、自动活动、原地遇敌、自动任务或冻结原对话直接拒绝，不清pending、claims、活动状态。当前基线没有另一个实时玩家交易容器；后续若添加交易锁须纳入同一拒绝边界。

仓库不进入original_items或original_instances，所以原ITEM谓词、背包容量、装备与战斗复活物品列表都排除仓库UID。远程UI只读SessionClient快照并发送link.request，没有backend；同角色设备通过既有Backend实例共享权威，多角色沿既有ProfileHub隔离。

当前固定3000不会随转数降容量。不擅自删除物品或启用原30格hook；未来切换更小容量必须先定义迁移/超额取出政策。本次未提高协议号，旧UI忽略新增字段，缺revision的仓库请求会被拒绝；旧装备/使用/丢弃命令仍只查当前随身容器。

## 验证与性能界限

仅运行定向套件，完整suite由主合并会话负责：

- `item_storage_test`：源标记允许/禁存、UID/耐久保真、装备先卸下、冻结pending、重复/非法整批拒绝、旧v6迁移、严格跨容器UID、真实`.tmp`保存失败和磁盘读回、原任务/战斗使用排除、65件=64+1、拆堆不扩背包、3000满仓、满包、旧计数与免费两向不扣币。
- `item_storage_ui_test`：端口0服务器、无backend真实GameScene、第二WsLink；1120×760/390×844真实鼠标多选存取、旧设备请求、保存失败/重试、满包/满仓、键盘输入拆堆数量、每次RPC后WS settle。profile重建的背包必须移到仓库之下：Godot GUI命中依控件顺序，不单看z_index。没有扩大修复其他面板输入。
- `item_storage_capacity_lan_test`：实际192000 UID全仓、完整profile JSON、磁盘读回、两个真实WS设备初次快照与拆取同步、第二设备旧revision拒绝。
- `inventory_ui_test`：既有背包回归。

最大容量此次机器实测：192000原实例、3000个64堆，**8,880,822字节**完整快照（包含真实其余基础profile字段）。32MiB的发送/接收队列剩24,673,610字节；不是对无限宠物仓库或任意大历史数据的无限承诺。客户端命令上限保持1MiB，Codec无额外快照截断；仅服务器outbound和客户端inbound从8MiB提升32MiB。现有拥塞后关闭重连逻辑保留。

本机日志测量：快照构造+编码2118ms；严格校验1315ms；保存+读回1978ms；两设备初次同步2810ms；拆3件并同步4510ms。此为极端满仓、当时CPU负载下的一次观测，不是延迟承诺。保留原UID的代价是O(物品数)完整profile复制/序列化，本期仍沿现有完整profile发布；UI每页15个仓库格，不一次创建3000行控件。

像素证据用静音离屏、不可聚焦窗口输出，不是headless渲染：

```sh
STONE_AGE_FOREGROUND_TEST=1 STONE_AGE_PROOF_DIR=/private/tmp/item-storage-shots ./scripts/run.sh --position -10000,-10000 --script res://tests/item_storage_ui_test.gd
```

`/private/tmp/item-storage-shots/`共10张PNG，逐张view_image核对：桌面背包入口、多选存入/取出；390×844多选、LAN旧选择、保存失败、满包、满仓、64堆输入3与拆完剩62。未提交PNG或导入资源。日志为`/private/tmp/item-storage-test.log`、`item-storage-visual.log`、`item-storage-capacity-lan.log`、`item-storage-inventory.log`。


## 集成旧版本fixture回归审计（92f0ec0）

集成 `original_quests_test.migration()` 出现8个失败：v1/v2/v3/v4各一次load失败、一次非默认药数量/位置保留失败。根因是测试从当前 `Session.snapshot()` 构造旧档，仅降低version并移除 `ORIGINAL_DEFAULT`，却携带新仓库的三字段；这不是历史旧档，而是v1–v4版本号与v6仓库schema混合。权威校验拒绝该组合是正确行为，不能为修测试放宽或静默丢弃仓库内容。

最小修复仅在该函数构造old fixture时移除 `Session.ItemStorage.FIELDS`，并断言迁移后空仓/revision=0；产品迁移、半缺schema拒绝和跨容器UID校验均未修改。独立 `item_storage_legacy_test` 同时调用整个原migration函数，另外覆盖v1–v6移除相应未来字段的真实可接受旧格式，以非默认药37、石币4321、位置2000(55,92)及通行证检查真正的读取结果。每个版本清理测试备份，使用全新Session读取并保存，再以另一新Session验证完整快照一致，避免沿用fixture会话或备份掩盖读取失败。混合版本、每种半缺仓库字段、重复UID磁盘档仍拒绝。

基于 `92f0ec0de48848004de44166875b0a888bd264e8` 的专项复现日志 `/private/tmp/item-storage-legacy-before.log` 精确8fail；修后 `/private/tmp/item-storage-legacy-after.log` 为0fail。只运行迁移专项，不运行并行代理正在修改的目录oracle；未运行full、未改main/live/真实存档。
