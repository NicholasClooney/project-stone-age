# 强恩洞窟20–22

固定源为 `references/chenmingbiao-stone-age` 的 `0c58fb6683a49a178a8ad845a8c296c2cb83bd81`。独立白名单见 `tools/jan_cave_quest_sources.json`，逐文件SHA、固定敌人原战术权重、七技能槽及异常技原行号见 `bonus-cave-chains-sources.json`。不扩展现有战斗AI或魔法系统。

## 原链和地图

- 吉德的朋友（3400，59,66）给花2486；吉德（3406，27,14）收花接20；儿子（3406，28,17）给发饰2487。
- 从加鲁卡200（285,926）进入20601（9,59），沿原三段楼梯到20604。四、五、六楼的精确口令依次为“红色月亮的光芒”“蓝色山脉即力量”“白色之风即速度”，原Warp依次为20605（4,71）、20606（64,3）、20607（7,5）。空格不裁剪。
- 20607的三处原守卫绑定各自保留，原敌队顺序961、963、962；均为dieact1，胜后Warp20607（36,31），没有固定物品掉落。原精灵顺序100230、100065、100436。失败存档不提交胜利Warp，重试沿现有结算事务。
- 携发饰见强恩（20607，68,5）完成20，发饰此时不扣。妻子（71,7）原说明保留。沙拉（20608，9,3）收发饰接21；先回强恩随机领2490–2494之一并完成22，再找沙拉取2488家书，最后吉德收家书给2489木笛并完成21。22原任务日志误称送家书，助手按实际领奖行为说明。
- 只启用20、21、22；吉德161后续分支和47不在白名单。随机五奖、满背包拒绝、重复交付及每个任务完成条件均由专属交易测试覆盖。

## 原重复传送格的依据

20607（75,13）在mapwarp.txt:2308与2310分别指向20608（0,7）/（0,8）；2309/2311是两条回程。固定源码version.h:219启用 `_MAP_WARPPOINT`，npc_warp.c:55拒建普通Warp NPC，Warp模板未绑定PostOver。mapwarp按行序尾插，EVENT_main:63–70找到OBJTYPE_WARPPOINT首条后break，因此本项目显式选择0,7，同时保留两条回程。完整源码SHA/行号在共享源审计；此结论不声称验证未知历史binary，也不套用NPC位置查询推断踩格。

## 项目助手和作用边界

助手属于项目便利。洞外单列公开入口步骤：仍绑定真实受审口令NPC供服务器查找，但显示加鲁卡原入口并仅返回200地图安全邻格，返回的 `npc_id` 为空，客户端不会继续追向洞内人物。洞内禁止助手代走，即使已经在同一房间，也必须亲自走到原对话距离。没有原自动执行，保持未开放。

`has_arrival` 检查原入口、连续原步行/楼梯/口令路线；`check_action` 检查当前动作和 `jan_final` 原守卫胜利资格。强恩与沙拉由公共策略检查最终战标记，父女两图正常原门往返保留资格。取得物品、任务标记、项目放置或保存再读回都不能伪造到达；合法到达证明仅为服务器内存，不增加原进度旗标或存档字段。

near与arrival均只返回服务器当前合法近谈格，不再选择另一邻格或同房间的远处落点。旧几何边界仍保留：墙、NPC、传送格不参与连通洪泛；原传送落点只采用唯一相邻区域，未知区域或地图失败关闭。步骤和raw npc_id重查权威状态。独立Jan导航键包括楼层/连通区、合法到达和当前可近谈NPC集合；普通同区且近谈集合不变的步行不重建助手，两设备在合法近谈变化时同步刷新。

奖励按原发放；原魔法、抗性、回避、三连及投掷特殊模式通过共享effects消费者标未生效。现有固定装备普通属性由公共OriginalEquipment定义生效。母亲的发饰2487现按原type13 EARRING使用已有饰品槽，固定魅力+2、耐久200000生效（itemset.txt:2070，item.h:25、item.c:1242–1245）；交给沙拉前须先卸下，原ITEM背包条件不因装备支持而放宽。无body槽、存档版本或魔法系统扩展。

## 导入与定向验证

本次合法到达/helper适配不改变源数据或素材，不需要重导。首次引入原任务或重建资产时仍需运行全部下列步骤，不能依赖代理槽已有文件：

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5
.tools/asset-venv/bin/python tools/import_world.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --fallback-source .tools/legacy/extracted/SA8.0-20260803
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --sprites 100436
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 100436
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

pack_frame_sheets含拆分索引。world导入重写共享图像后必须重新palette_images。20601–20608全部锁原地图SHA；六处已恢复原NPC脚本从旧景观传送中移除，不能保留免费绕过口令/守卫的旧传送。

- `tools/test_jan_cave_quest.py`：精确绑定、分支、物品、三个守卫、三道口令、地图和重复出口。
- `jan_cave_exchange_test`：原交易、五随机奖励、回滚、满包及先22后21、存档读回；洞内交易前走真实原入口/口令/守卫/父女传送，不再注入洞内坐标。
- `jan_cave_route_test`：真实原入口和连续步行、三口令、三守卫实际敌队、结算保存失败与重试、双socket旧token/伪造敌队拒绝；只允许公开入口外的测试接近位置，不授予scope或mark。
- `jan_cave_navigation_test`：两mode公开入口不携带洞内目标，项目放置/旧step/rawNPC不能伪造路线；合法近谈最终落点保持原地/同区；两socket在真实路线后刷新。
- `jan_cave_walking_test`：GameScene从公开入口外实际踩门，并连续走三段原楼梯到首个口令层，验证到达证明随真实步行保持。
- `jan_cave_ui_test`：390×844真实远程客户端，实际点击公开入口、沿全部楼梯与洞内路径行走，三道口令以真实中文键盘输入，战斗、20→22→21父女原门往返与奖励库存均实际操作。没有洞内放置fixture，也不以headless代替像素证明。

仅定向验证，不在代理槽运行full；截图不提交。
