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

助手属于项目便利。洞内仅允许当前楼层、当前可达连通区域的目标；不能从村庄或早期楼层跳过口令/守卫。最终near和arrival落点均由独立Jan模块筛选，所有NPC/墙/传送格不参与连通洪泛。角色恰在原传送落点时，仅采用唯一相邻区域；未知区域拒绝导航。任务步骤和直接npc_id命令都重查服务器位置，没有新增进度旗标。两设备共享阶段更新，同区步行不广播任务助手重建。

奖励按原发放；原魔法、抗性、回避、三连及投掷特殊模式通过共享effects消费者标未生效。现有固定装备普通属性由公共OriginalEquipment定义生效。母亲的发饰2487现按原type13 EARRING使用已有饰品槽，固定魅力+2、耐久200000生效（itemset.txt:2070，item.h:25、item.c:1242–1245）；交给沙拉前须先卸下，原ITEM背包条件不因装备支持而放宽。无body槽、存档版本或魔法系统扩展。

## 导入与定向验证

主合入后需运行全部下列导入步骤，不能依赖代理槽已有文件：

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
- `jan_cave_exchange_test`：实际原交易、五随机奖励、回滚、满包及先22后21、存档读回；注入NPC邻格/交易fixture，不冒充步行。
- `jan_cave_route_test`：真实原口令、三敌战斗、结算保存失败与重试、双socket旧token/伪造敌队拒绝；门间位置是明确fixture。
- `jan_cave_navigation_test`：原地图所有洞内NPC两mode最终落点同区、旧step/rawNPC拒绝跨层/跨守卫、地图失败关闭、两socket阶段与同区不广播。
- `jan_cave_walking_test`：生产移动实际走三段楼梯、各原口令落点到下一道门/守卫、战胜落点到20608及原出口走回。各独立区段起点是源Warp fixture，不伪称从村庄连续自动行走。
- `jan_cave_ui_test`：390×844真实远程客户端、实际按钮/中文按键、三口令、三敌像素、20→22→21和奖励库存；原入口/楼梯用原格触发fixture，连接步行由上一个suite覆盖。

仅定向验证，不在代理槽运行full；截图不提交。
