# 红飞骑乘方案 C：空间遮罩小样实验（未接入）

2026-10-04，基于 `main` 的 `930a9249`。本页记录项目衍生外观研究，不代表已开放红飞骑乘。工具只生成审阅图，不生成游戏资源清单；骑乘条件、造型映射、速度、证书、Session/backend 和存档均未修改。

## 结论与实际范围

跨十二人物体型的像素共识能产生外观接近目标的小样，但**目前不能独立证明所有骑手像素保持 bit-exact**。不能把“候选遮罩外像素不变”当作“非龙像素不变”；前者只证明实现遵守自己的遮罩，后者需要独立的人物/龙归属证据。本实验状态为 `UNPROVEN_NOT_FOR_IMPORT`，禁止据此接入或上线。未宣称自动分割一定不可行。

已解析原黄飞十二合成号 `101307+8*body`：每体型 104 clip（13动作×8方向）、440帧位置、368不同位图，总5280位置/4416位图。只解码216张小样来源位图，没有运行全套生成、Godot重导入或长测试。演示采用体型1/8（101315/101371），动作3/4/0（站立/行走/攻击），方向2/4/6，首帧及中帧，共36组原图/候选红图/遮罩。

裸红飞100360与裸黄飞100362轮廓、动作时序不同。本方案即使最终成功仍是**黄飞轮廓和时序的项目派生红色**，不是原生红飞合成图。小样用原红飞实际出现的224–233红色阶重映射黄/褐色阶；它不是原版同图调色表。白色腹部、牙齿、阴影未重新分区；翼膜部分颜色仍保留。小样不是最终配色验收稿。

## 可复算方法

```sh
PYTHONDONTWRITEBYTECODE=1 .tools/asset-venv/bin/python tools/audit_red_dragon_recolor.py \
  --source .tools/legacy/extracted/SA8.0-20260803 \
  --output /private/tmp/tmux-agents/red-dragon-riding-recolor/samples
PYTHONDONTWRITEBYTECODE=1 .tools/asset-venv/bin/python -m unittest discover \
  -s tools -p test_audit_red_dragon_recolor.py
```

工具读取原RD索引像素，以ADRN锚点和SPR帧偏移对齐十二人物的同动作/方向/帧。目标像素与至少6体型一致才列为候选，且只改变指定黄褐色阶。另计12体型全同阈值供比较。输出只写 `--output`，不调用导入器、不输出pair或manifest、不使用AI重画和手工改像素。

36组小样均通过重复计算hash、透明掩码一致、候选遮罩外索引一致；三处既有独立人物小矩形的变化数为0：251083 `(45,23)-(56,35)`、250967 `(39,25)-(47,35)`、272413 `(39,12)-(46,20)`。这只是三个局部标签，不覆盖全部头发、衣服、手脚或其他帧。测试包含一个合成反例：即使12体型同色，同色本身也没有语义标签，不能据此保证骑手未变。

两次完整小样生成的PNG hash清单和实验JSON逐字节一致；216条抽样原RD记录生成后重新读取，hash不变。十二张原黄飞导入sheet与主checkout逐张hash相同。只验证抽样RD及索引/SPR/palette和十二黄sheet，没有宣称扫描或核算整个2GB REAL。

## 具体未解歧义与最低补充方法

- `101315 / 0_2 / frame 8 / bitmap 250973`：骑手小腿右边缘与龙身/后肢的接壤处，原大小左上原点 `(51,67)`、`(51,69)`、`(49,72)` 为索引81/80/81，与8体型相同，因此被候选改色。视觉能定位接壤区，但原图不带标签，无法仅凭这8票认定该阴影边缘属于龙还是人物轮廓。**这是待归属的具体点，不是已经证实改坏人物的断言。**
- `101315 / 3_6 / frame 0 / bitmap 251175`：龙翼根贴着人物手臂/腰部，头发和背后耳翼也相邻；候选红色仍保留部分翼膜原色。
- `101371 / 4_6 / frame 0 / bitmap 272413`：人物手、腿跨越龙胸/翼根， `(35,50)` 与 `(37,52)` 同为213，分别7/10体型一致。不能用统一上下矩形或仅黄色阈值证明归属。

最小补充不是再降低共识阈值，而是建立**独立、可审阅的空间标签**：针对要改色且靠近人物的连通片记录人物保护多边形/龙区域多边形或逐行区间，绑定源bitmap hash；脚本栅格化标签并保守排除不确定边缘。标签可以由人审阅规则生成，仍由脚本执行重着色，不需要手绘成品。可复用的同龙姿态标签必须逐体型处理遮挡差异；不可因相同颜色直接沿用。

要证明全套，最终需覆盖4416个不同源bitmap（440帧位置可以复用同一bitmap标签）的所有改色区域与骑手边界；同姿态复用可减少标签数量，但当前证据不足以给出更小的必需标注张数。每帧需有 `changed ⊆ independently_reviewed_dragon`、`changed ∩ protected_rider = ∅`、透明/几何/帧序/时序一致，并对标签外待判定区域保持原样且显式报告未完成。全套扫描和目视验收之前不能把小样外推为全套证明。

## 未来导入接点（尚未修改）

1. `tools/import_riding.py`：从现有100362 pair深拷贝人物、certificate=2及同体型关系，生成100360派生pair；使用明确项目命名空间，不能冒用缺失原104137–104148编号声称原图恢复。派生sprite/bitmap必须避免与原图编号冲突。
2. `find_composite` 对派生来源读取13动作；当前普通黄图仅通过通用battle过滤器导入9动作，不能据此忽略其余原动作。派生图单独解码/入sheet，绝不覆写黄图decoded缓存或sheet。
3. `write_sheets` 和manifest增加来源及派生标记，由 `split_riding` 生成index/composite；现有actor/battle/remote读取接口可复用。界面与更新日志必须明确项目改动、黄飞轮廓派生。
4. `riding.gd` 按pair读取，黄飞相同certificate和体型集合自然复用现有忠诚、等级、骑术、出战互斥、存活、速度和战斗规则；本实验未改任何规则，也未完成红黄规则等价运行测试。
5. 用户图像确认之后才可集成。后续需独立验证全体型帧覆盖、复算hash、骑手真值、黄图不变及规则等价，并按主代理窗口运行定向测试；本次没有full/main/live/save动作。

## 原资源搜索范围

完整前置报告位于 `/private/tmp/tmux-agents/red-dragon-riding-audit/report.md` 和 `/private/tmp/tmux-agents/red-dragon-assets-search/report.md`，本轮已完整阅读。104137–104148在本地99ds 2.5/8.0、公开旧社区满补丁115索引、华义StoneAge85.msi所含137索引中均未找到；源码/Lua存在编号映射不等于资产已取得。热血部落公开PC链接本次不可获取。没有扫描所有无引用REAL残片，没有穷尽所有历史/私服/8.5资源，更不宣称全网不存在。

审阅材料：`/private/tmp/tmux-agents/red-dragon-riding-recolor/` 下 `samples/comparison-action-{3,4,0}-{first,middle}.png`（六张均已逐张view），`samples/experiment.json`、`samples/image-hashes.json`、`verification.json`、`ambiguous-points.json`、`samples/boundary-details.png` 与 `samples/coordinate-250973.png`。图片不入Git。小样图是源资产离线解码，没有真实游戏渲染验证。
