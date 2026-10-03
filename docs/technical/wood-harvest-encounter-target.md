# 伐木助手落点与原地遇敌生产复核

基线：`b59904c`（包含已上线原地遇敌）；不依赖第二阶段未上线策略。

## 已证实根因

伐木第7步旧目标 `200 (644,345)` 位于 area88 的矩形中心，却同时落在先出现的 area87 中。两区 priority 均为1；原源码 `gmsv/char/encount.c:378–401` 仅在新优先级**大于**旧优先级时替换，所以生产 `EncounterCatalog.area_at()` 正确选中 area87。area87 没有树怪 group414。此前助手仅核对矩形包含关系，导致「到采木区域」实际落在不能遇树怪的覆盖区。

| 原数据 | 矩形（含边界） | 选择与条件 |
| --- | --- | --- |
| `encount.txt:61`，area87 | `[550,282,652,403]` | 同优先级先出现，644,345选中它；无414 |
| `encount.txt:62`，area88 | `[516,238,772,452]` | 653,345选中它；228/231/233/414权重1/1/1/3 |
| `group.txt:301`，group414 | — | `requires_item=2478`（采伐许可证），enemy563 |
| `enemy.txt:387`，enemy563 | — | 原树怪「木」，掉2468良质木材，原生成时700/1000抽样 |

两区 `event_now=event_end=-1`，因此这次**不是**「原版遇敌条件尚不支持」拒绝。持证阶段为 END18、END19、背包2478；树怪抽组只检查许可证，不以 NOW18/19 或斧头作新增条件。原源码 `char/enemy.c:1297–1332` 遍历 `0..<CHAR_MAXITEMHAVE`，原定义包含装备和背包、不含仓库；当前生产普通走路接口使用 `original_items` 背包。既有装备槽未接入遇敌持物检查的限制见 [木材掉落审计](../reverse-engineering/original-wood-drops.md)，本修复没有扩大该范围。

## 修复范围

仅修改 `QuestHelper.harvest_step()` 的落点选择。从原助手可走落点按原地图碰撞、NPC占位和传送格限制搜索同一连通分量，并以生产 `area_at()` 确认实际命中原木材area。得到 `200 (653,345)`，距旧落点9格，原矩形/优先级/概率/条件/组与掉物表均未改。

几何结果按遇敌目录实例、任务目录实例、已启用任务、NPC状态版本与area缓存，避免每次背包/战斗发布重做搜索。没有改动 Backend、automation、profile hub、客户端输入、stationary控制器或其停止语义。

## 生产路径验证

`stationary_production_test.gd` 使用生产 GameScene、真实127.0.0.1 WebSocket随机端口，客户端 `world.backend==null`。Backend正常逐帧处理；从未人工调用 `_process()`、`stationary.tick()` 或手工发keepalive推进遇敌。原地开关与继续探索通过真实鼠标事件，普通走路通过GameScene键盘输入。战斗出招经过真实远程battle_command和生产结算，不手造战果。

fixture明确限定为：已完成前六步的END18/19、背包许可证、15级角色；GM力量10000用于短时间验结算，不用于平衡验收；隔离 `user://stationary-production-save.json`；记录的原RNG种子。旧坐标种子918约2.5秒自然普通开战，说明本轮未复现「完全不遇敌」。新坐标种子0，原step/roll第19次选中414并产生2468，约9.6–9.9秒自然开战，跨越5秒租约且每秒由同一负WebSocket实例ID续期。

覆盖桌面1280×720及390×844：真实开关→助手自动关闭→站立→树怪→真实胜利→木材保存→继续探索→无需重开开关进入下一场。两个尺寸各完成两次木材胜利，之后键盘在653,345和654,346之间普通行走再次遇树怪并保存第五根木材。磁盘JSON数字先规范成int再比数量，避免把JSON float与内存int的Array.count差异误判为保存失败。

同坐标report_position、窗口设置保存和生产后台ping未停遇敌；真实设置菜单、助手旅行动作、手动移动会停；断线自然租约到期会停。既有 `stationary_encounters_test.gd` 保持覆盖不遇敌/自动任务/组队互斥、位置边界、保存失败、逃跑/战败及异连接无法续租。`quest_helper_test.gd` 继续验证真实任务访问RPC与客户端投影。

实际OpenGL Metal静音离屏截图逐张检查；屏外窗口不可聚焦。手机助手新坐标和按钮可读可点；原战斗舞台在窄屏保留既有缩放和黑边，未声称重做全部战斗HUD或实体验证触屏。运行方式：

```sh
./scripts/run.sh --headless --script res://tests/stationary_production_test.gd
# 仅在已获授权的离屏视觉验收中：
STONE_AGE_FOREGROUND_TEST=1 ./scripts/run.sh --position -10000,-10000 \
  --script res://tests/stationary_production_test.gd -- --visual-review
```

截图输出 `/private/tmp/stationary-production-render/`，不提交图片或原资产。新套件登记在默认测试清单；本任务按要求仅跑定向套件，不跑full、不改main、不重启live、不读取或写入真实玩家存档。
