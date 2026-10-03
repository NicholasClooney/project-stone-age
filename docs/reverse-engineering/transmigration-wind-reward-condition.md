# 玄黄使者奖励条件：第一阶段接口审计

协调已明确：用户决定前按方案B，核心41→42继续，三档可选献宠奖励保持关闭，不造替代奖励。

这项可选奖励尚未实施；没有修改原条件或另造替代奖励。此次调查不是原服完整运行记录。

## 锁定来源

- `gmsv/data/npc/sainasu/event/genou_2` SHA256 `094b5f439dddf2f12b34218a1e3f4ee3356d1ef7e45e44ca759e1ebcc71b7106`。
- `gmsv/npc/npc_exchangeman.c` SHA256 `89fbfab08d473d6dc772cac08d93e9f9f4b100fbe04a211314e7293bcc9d4435`。
- `gmsv/util.c` SHA256 `fb2fc8a071d7f67125458cce882f74354d308f9682ca9ad0c7183a351c40d18b`。
- `gmsv/npc/npcutil.c` SHA256 `47dd685fc91b2aa686c45a03e4fe49586649b345d6ab8c4bbf8da729e4c1064b`。

`genou_2:9–18` 第一奖励分支（源索引0）的条件为：

```
LV>0&ENDEV=42&ENDEV=4&PET>60-95,&ITEM=2758LV>0&PET>59-95&ITEM=2758
```

## 原 C 实际选择

`tools/audit_transmigration_conditions.py` 从上述 SHA 固定源文件逐字提取 `ScanOneByte`、`getStringFromIndexWithDelim_body`、`NPC_Util_GetStrFromStrWithDelim`、`NPC_EventFreeIfCheck`、`NPC_EventBigSmallCheck`、`NPC_ExChangeManEventCheck`，用 cc 编译。角色查询用单只普通布鲁顿、等级/旗标/背包手环的最小桩；没有声称复现完整服务器、宠物删除或随机奖励。

- `util.c:949–1002` 对开头的 `&` 返回成功且空字符串，并非跳过空字段。
- `npc_exchangeman.c:623–668` 外层逗号 OR，内层 `&` AND；第二个 OR 的首项为空，`NPC_EventBigSmallCheck:674–735` 无比较符返回 FALSE，所以整个第二个 OR 为假。
- 即使移除开头 `&`，`ITEM=2758LV>0` 也不会被解析成 ITEM2758：比较分发先见 `>`，将左侧 `ITEM=2758LV` 传给 `NPC_EventFreeIfCheck:741–802`；它只做精确字段名比较，也为假。不能通过把数字截断成2758解释这个粘连字段。
- 第一 OR 则完全正常：人物LV>0、END42、END4、普通模板95宠物LV>60。**这一 OR 根本没有手环条件**，因此满足时即使没有2758也会选中第一奖励分支。

最小 C 输出（完整可重跑）：

```
leading-empty token=[] predicate=0
glued predicate=0
flags=0 bracelet=0 pet=42 -> branch=-1 alternative=-1
flags=0 bracelet=0 pet=43 -> branch=-1 alternative=-1
flags=0 bracelet=0 pet=60 -> branch=-1 alternative=-1
flags=0 bracelet=0 pet=61 -> branch=-1 alternative=-1
flags=0 bracelet=1 pet=42 -> branch=2 alternative=2
flags=0 bracelet=1 pet=43 -> branch=1 alternative=2
flags=0 bracelet=1 pet=60 -> branch=1 alternative=2
flags=0 bracelet=1 pet=61 -> branch=1 alternative=2
flags=1 bracelet=0 pet=42 -> branch=-1 alternative=-1
flags=1 bracelet=0 pet=43 -> branch=-1 alternative=-1
flags=1 bracelet=0 pet=60 -> branch=-1 alternative=-1
flags=1 bracelet=0 pet=61 -> branch=0 alternative=1
flags=1 bracelet=1 pet=42 -> branch=2 alternative=1
flags=1 bracelet=1 pet=43 -> branch=1 alternative=1
flags=1 bracelet=1 pet=60 -> branch=1 alternative=1
flags=1 bracelet=1 pet=61 -> branch=0 alternative=1
```

## 奖励、消耗与顺序

`NPC_TypeCheck:248–287` 原脚本顺序首个满足者胜出：

| 原分支 | 实际可选条件（人物LV>0，单只普通95宠） | 删除声明 | 随机奖励原表 |
|---|---|---|---|
| 0（9–18行） | END4+END42 且宠≥61；不需手环 | `PET>59-95*1`、2758 | 73,173,375,574,774,973,1075,2695 |
| 1（20–29行） | 宠≥43且有2758；第二OR不需END4/42 | `PET>42-95*1`、2758 | 67,167,271,473,676,872,1175,2691,167,271,676,872,1175 |
| 2（32–41行） | 宠≥1且有2758；第二OR不需END4/42 | `PET>0-95*1`、2758 | 71,171,372,571,772,972,1074,2694,71,171,372,571,772,972 |

等级61且有双旗标时高档先于后续分支；60级即使有双旗标也落入中档，不能据删除声明`>59`把高档准入改为60。多只宠时条件检查与删除分别扫描，存在检查≥61却删除另一只≥60的可能，尚未纳入最小单宠桩；第二阶段需专门裁定/审计UID绑定。原`NPC_EventDelItem:3257–3366`扫描持有的指定道具，缺物品并不创造新道具；本次未运行完整奖励事务，故“无环选中”是已实测选择结果，不把它夸大成完整领奖实测。

另两档原条件显式带不检查END4/42的OR；也是经济/前置差异，不能只因语法正常就自行改成全部要求四精灵完成。当前所有三档仍未激活。碧青的已批准OR是另一项，不自动授权这里。

## 核心41→42不依赖可选奖励

- 实际`genou/genou.create`绑定威尔到`genou_1`、姆哈萨到`genou_3`；END41和竖琴2736由梦德既有实例`sainasu/event/event12`原分支3取得。
- `genou_1`原分支0检查END41+END4+2736+NOW42，收2736、给2735、END42；不引用2758或`genou_2`奖励，也不要求交宠。
- 两名风使者才绑定`genou_2`，属于完成风链后的可选献宠奖励。底座提供共享实例分支合并接口，第二阶段风链可独立完成核心41→42，且保持上述奖励未实施，等待用户裁定。
