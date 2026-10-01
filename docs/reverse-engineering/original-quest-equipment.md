# 伐木与药草任务装备

以本地 `references/chenmingbiao-stone-age/gmsv` 为规则依据，装备通过服务端
`GameSession.equip_item("original:<uid>")` 执行。客户端只读快照并发送命令；
远程客户端不持有 backend。只有已核查的四件任务装备开放装备，不把其他
原道具自动变成装备。

| itemset 行 / ID | 原类型 / 槽 | 等级 | 攻 / 防 / 敏 / 魅 | 最大磨损耐久 |
| --- | --- | --- | --- | --- |
| 2048 / 2465 哈恩的斧头 | AXE 1 / ARM | 25 | +35 / -15 / -15 / 0 | 0，无战斗磨损 |
| 2068 / 2485 哈恩改造的斧头 | AXE 1 / ARM | 25 | +33 / -10 / -10 / 0 | 300000 |
| 2064 / 2481 杉的手环 | BRACELET 8 / DECORATION2 | 30 | +8 / +5 / -5 / -5 | 2500000 |
| 2010 / 2427 老爷爷的护身符 | AMULET 15 / DECORATION1 | 10 | 0 / 0 / 0 / -1 | 2500000 |
| 2067 / 2484 折断的斧头 | OTHER 16 / 不可装备 | — | 全 0 | — |

原表随机范围均为固定值。`dambreak=-1` 是使用次数，不是磨损耐久；当前/
最大磨损取第30/31列，改造斧不能根据名字推断为更高攻击。武器共用 ARM，
所以斧头与 club 互斥；两个饰品不能同 type。手环与护身符可同戴，2427 与
镜子、已有精灵护符等 AMULET 双向互斥。旧 body 精灵装备仍用已有槽。
依据 `item/item.c:1216–1260`、`char/char_item.c:344–402`；原
`menu.cpp:8940–8973` 的 ARM 中心61,129、饰品1中心32,68、饰品2中心83,68
直接用于道具窗口，未补造装备位置。

**2427 的六状态耐性尚未生效。** 原表的毒、麻痹、睡眠、石化、酒醉、混乱
耐性都为 +2，保存在 `OriginalEquipment.ITEMS[2427].resistances`，按实装
实例汇总到 `OriginalEquipment.resistances(profile)`，战斗 config/state 的
`player_resistances` 及组队成员 `resistances`。当前引擎没有六状态施加、
命中率、回合持续与行为系统，因此这些字段仅是原数据接口，不宣称已有
防状态效果；道具界面也明确提示未生效。未新增伪造状态攻击测试入口。

## 实例、存档与任务

`SAVE_VERSION=6` 保留 `original_items` 整数列表作为持有投影，工具/许可证
遇敌检查继续读取它；一一对应的 `original_instances` 存 uid/item_id/
durability，`next_original_uid` 单调分配。`original_equipment` 保存 arm/
bracelet/amulet 的 uid。固定属性、原最大耐久从经核查的定义读取，载入不
重抽也不恢复已经磨损的副本。新版校验拒绝投影不一致、重复 UID、不存在
的装备引用、错误槽、非法耐久、同槽冲突和超过15个未装备背包格的存档。

旧1–5版存档迁移只按旧持有整数逐件建立实例；旧 club/mirror 布尔和 body/
amulet 字符串、库存数量保持不变，不增加装备数量、不自动装备原道具。
原道具全量持有上限18包括三个已装备原件，背包仍15格。损坏、丢弃、任务
交易都同步实例与装备引用；脚本 DelItem 扫已装备副本再扫背包，带数量的
删除只消费指定数量。丢弃命令可带 `instance_uid` 精确指定副本。新领取/
掉落只建立新实例，不重置原有副本。非法主存档沿用有效 `.bak` 回退。

## 战斗磨损与属性

`battle/battle_event.c:318–355,390–489,623–643`：正物理伤害才磨损。攻击者
选 ARM；防御者按 BODY 50%、HEAD 17%、DECORATION1 17%、DECORATION2 16%
选择，空槽按原五槽次序轮转并跳过 ARM。有旧 body/amulet 时保留真实占槽，
不错误地把每次打击都分给手环。最大耐久<1不扣，原斧不会变成故事断斧。

武器先取 C 整数截断 `(damage-50)/40`，小于等于0时用1；其他槽先取
`(200-damage)/20`，小于0时用1，保留原代码覆盖 `damage>=200` 赋值的细节。
实际扣值用原 RAND 宏的浮点上界范围。70/50/30%的阶段为完好/受损/毁坏/
不堪使用，只提示，不降低装备属性；原减属性代码已经注释。耐久耗尽直接
删除物品并卸下，不生成2484。2484来自20501ev3交原斧的故事交易，20501ev1
用它换2485，不能以磨损伪造该交易。

战斗 admission 汇总攻防敏魅，魅力用于捕获与宠物忠诚衍生，不永久改低
角色基础魅力。组队各成员只磨损并结算自己的实例；攻击、反击、受击与
骑乘伤害使用真实 resolver。损坏后从原基础属性加剩余装备重新计算，避免
已钳制的防御/速度直接减去修正造成错误。普通结算、单木已有 resume 状态
保留实际副本耐久；重启后按当前实例重新计算属性，避免从 admission pending
恢复已经损坏的斧头加成或武器动作。不扩大现有组队拓扑重启恢复范围。

## 原斧动作与资源重导入

`tools/import_characters.py` 按原 `gmsv/char/char_data.c` 的
`CHAR_eqimagetbl[][5]` 配对 `include/anim_tbl.h` 中 SPR_em/SPR_ax/SPR_cl，
不使用数字 +1/+2 猜测映射。范围仅48个经典角色100000..100235；本地2.5包
原已缺少100100的有效帧，仍导入47个角色与对应斧动作。缺斧动作不会新增
删除其他可用角色的行为。battle view/下载依赖按实际 ARM 的 axe/club/
空手选原动作；未做渲染像素验证。AXE/CLUB/CLAW 反击系数来自
`battle_event.c:2744–2821` 的 CounterTbl。

主 checkout 整合后需重跑（资源始终 gitignored）：

```sh
.tools/asset-venv/bin/python tools/import_characters.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_battle_sounds.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle characters
python3 tools/split_manifests.py
```

任务物品名称/图标仍由现有 early-quest importer 提供；本提交未改它的字段
或药草任务来源配置，药草任务分支整合后由主会话按其变更重导入。

真实验证：`original_wood_equipment_test.gd` 覆盖精确值/等级/互斥/包格/
旧存档迁移/副本耐久/真实solo与party结算/精确丢弃/远程真实点击与斧动作。
相关既有套件覆盖任务领取、脚本删除、掉物、resume、精灵、忠诚、战斗、
角色选择和界面。本次按父任务要求只跑相关套件，整批 full 留给主会话。
