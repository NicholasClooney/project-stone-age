# 转生外围：忠诚与装备

第三阶段 E；基线 `6da4b47`，与 I 的 `stage-three-contract.md` v1 对齐。此片提供纯规则和候选 API，不开放精灵王服务，不改 Session/backend 调用点或存档版本。I 统一接线；完整服务只可随 `integrate/stage-three` 验收后发布。END53 关闭、MAX_GOLD 十亿、未知旧正转历史保护、物仓 3000 和等级上限 120 均不由本片修改。

## 原源审计

根：`references/chenmingbiao-stone-age/gmsv`。七个原文件的 SHA256、原 itemset 行号和算术矩阵见 `client/tests/fixtures/rebirth_peripheral_source.json`；无需导入新素材。

- `char/char.c:2923–2941`：base 先赋整数并上限 100，加入 `VARIABLEAI * 0.01` 再向零截断；主人 `TRANS > 0` 后加 `(CHAR_MAXUPLEVEL - LV) / 2` 整数补偿，最后限制到 0–100。
- `include/char_base.h:41` 实际定义 `CHAR_MAXUPLEVEL 140`，不是将项目等级 120 代入的推断。一级补 69；一次或五次转生相同；141 级负整数除法得到 0，142 得到 -1。超过项目等级的测试只核原算术边界，不开放该等级。
- `battle/battle_event.c:3435–3442`：捕获先 compliance，再按 clamped WORKFIXAI 的超 60 部分建立 VARIABLEAI 债务，临时 WORKFIXAI 压 60。其后常规刷新可以不同：主人 Lv1、魅力 60，宠 Lv1/modai100，正转时先得 100、债务 -4000，常规重算得 95。不能为了再次强制 60 改写 VARIABLEAI。
- `char/char_item.c:344–354`：`TRANS <= 0` 才核 ITEM_LEVEL；原 CHAR_STR/DEX 与 ITEM_NEEDSTR/DEX 直接比较，所有转数仍核 ITEM_NEEDTRANS。STR/DEX 不先除以 100。
- `include/version.h:234` 实际启用 `_ITEMSET4_TXT`；`item/item.c:326–332` 映射零基列 22=level，26/27/28=need_strength/need_dexterity/need_transmigration；ID 为列 16，cost 为列 18。
- 当前 `OriginalEquipment.ITEMS` 精确 166 项及 `Spirits.ITEMS` 精确 5 项，三种需求源列均为 0，空原列按原初始化的 0。现有定义省略这些字段等价于 0；未来非零定义使用相同检查。384 行非零门槛矩阵仅验证原 C 规则，不宣称当前装备存在该门槛。

`rebirth_peripheral_oracle.c` 独立输出 1800 忠诚/捕获和 384 装备判断金样。编译需 `clang -std=c11 -O0 -fno-fast-math -ffp-contract=off`：arm64 默认 FMA 可能把乘加合为一步，造成向零截断边界不同。本片保留现有 GDScript 的分步 double 运算，零转结果不变；这不是对未知旧服务器编译 ABI 的证明。

## E API

```gdscript
Loyalty.value(owner_level, charm, pet_level, modai, variable_ai, owner_transmigration: int = 0) -> int
Loyalty.capture_variable(owner_level, charm, pet_level, modai, owner_transmigration: int = 0) -> int
Loyalty.refresh(pet, player, owner_transmigration: int = 0) -> void
OriginalEquipment.definition_error(player: Dictionary, definition: Dictionary) -> String
OriginalEquipment.equip_error(player: Dictionary, item_id: int) -> String
OriginalEquipment.revalidate_after_transmigration(candidate: Dictionary, bag_capacity: int = 15) -> Dictionary
```

仅 `player.transmigration` 为规范转数；E 不读 `rebirth` 历史，不猜 equation、旧轮属性或旧 VARIABLEAI。旧参数调用默认零转，`refresh` 只改派生 `loyalty`。`legacy_unknown` 的已知正转数同样享有原忠诚与等级豁免，但是否允许再次转生由 I 判定。

装备成功返回 `{ok:true, profile:Dictionary, unequipped_uids:Array}`；失败仅 `{ok:false, reason:String}`。输入为完整现有 profile shape。先核 UID/槽位/耐久/互斥，再在深拷贝上逐槽重验；非法项只卸装，不删物，不自动仓储。净容量完全沿 `Session.bag_slots`：original_items 包含 worn，扣除 worn UID；计数式 legacy 物品只在仍有未穿副本时占格。超过容量整体拒绝，输入不变。

五槽保留原 UID/磨损；候选路径绝不调用 `migrate`、补耐久或重造 UID。legacy `equipment.body/amulet` 使用同一等级规则；club 与独立 mirror flag 保留原拥有/计数语义，不新增过去没有的门槛。BODY1052 互斥、2450 独立复活物品不变。`OriginalEquipment.valid` 对所有已穿五槽使用统一要求；结构错误、错槽、已损坏穿戴不能以卸装静默修复。

此候选 API 是项目原子安全补充，不冒称原 C 的转生副作用。当前正转 166 项均合法；容量卸装分支用合法的零转低等级候选验证，未虚构正转掉落非法装备。完整 profile、仓库 UID 唯一、保存失败及网络权限仍须 I 的既有验证，不由此函数代替。

## I 接线清单（基线行号，仅供定位）

| 调用处 | 接法与约束 |
| --- | --- |
| `game_session.gd:621` `_refresh_loyalty` | owner 保持装备魅力修正；给 pets 和 pet_storage 的 `refresh` 同传规范 count。不得再补第二次。 |
| `game_session.gd:498–560` 捕获 | 战前主人 level/charm 对应的 count 同传 `capture_variable`；保原债务初始化顺序，不将正常刷新结果强制 60。 |
| `original_quests.gd:356` 奖宠 | 候选 player count 传 `refresh`；不改变奖励原始成长/技能/VARIABLEAI。 |
| `game_session.gd:145/161/587/1386/1462` | snapshot、战斗配置、结算、load 已汇聚 `_refresh_loyalty`，在统一处接，不各复制公式。 |
| `game_session.gd:265` `preview_wild_battle_config` | 预估复制完整 profile 到 Session，保持 count，走与真实战斗相同刷新；自动捕宠也复用该入口。 |
| `game_session.gd:1731/1786` 骑乘检查 | `riding.can_mount` 只读派生 loyalty；确保调用前统一刷新，包括直接 mount 命令。不在 riding 再加补偿。 |
| 仓库存取、`original_charm.gd:41` | 前者保持随身/仓库宠统一刷新，后者现已调用 `_refresh_loyalty`；VARIABLEAI 保留。 |
| `battle_session.gd:330` | 读取 snapshot.loyalty，无新公式。 |
| `game_session.gd:728–751` 原 UID 装备 | 原等级单独检查替换为 `equip_error`；脱下分支、槽互斥、容量保持。 |
| `game_session.gd:771` legacy Spirit | 原等级检查替换为 `definition_error(player,data)`；club/mirror flag 不新增门槛。 |
| 转生候选结算 | 先写新 level/base/count，再调用候选重验，失败整笔拒绝；成功接 `profile`，之后有效 HP/忠诚和完整 Session 验证、原子 save。不得为完成结算调用 equipment.migrate。 |

`Loyalty.migrate_pet` 的既有零转旧形状兼容保持；已有 VARIABLEAI 不重写。未知旧正转不凭新补偿倒推历史债务。I 自行负责完整 Save v7/重试/replay/LAN 验收，本片仅声称纯规则/候选与旧定向套件已验。

## 验证

新增并注册 `rebirth_peripheral_rules_test` 与 `rebirth_equipment_candidate_test`。前者精确 C 金样、全 166+5 源定义、默认零转、正转数矩阵；后者五槽/legacy/净容量/输入及返回深隔离/UID/耐久/1052/2450。旧定向 `loyalty_test`、`transmigration_equipment_test`、`body_equipment_revival_test`、`original_helmet_equipment_test` 全通过；所有日志检查退出状态和 `SCRIPT ERROR`/`ERROR:`/`FAIL:`，不能只凭 Godot exit 0。无 UI/full/live 测试。
