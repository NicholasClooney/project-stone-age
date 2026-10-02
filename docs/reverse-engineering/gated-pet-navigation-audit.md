# 新增任务门与捕宠目标只读盘点

基线4854c86，pool-b/fix/burkel-hunt-navigation。未改变玩法。按主会话指示先将现有梦幻原门路线接入Lv1导航测试；捕宠便利是否绕门仍待用户裁定。A只描述本次梦幻导航测试的现状，不代表全局所有门已统一拦截。

## 根因及决策边界

- 柏克尔原点未变：41(47,54)，area408，enemy1092/template65。地图70×70，重跑build_level_one_spots仍生成同一点。失败是TimePassage拒绝从1000直接进入41并回推80,90；不是bounds、图片或敌表丢失。
- 生产PetEncyclopedia.catch_plan共1248个可用地点；要求检查的区域内87条。当前Lv1索引139条，其中关注区域6条；rare补充在关注区域仅卡卡金宝一条。以下不只检查Lv1。
- **梦幻41 area416 / 42 area427的(34,35)，呼拔拔72、卡比特111，是终战后领奖组件。** 41点组件12=胜Warp(34,39)组件12；42点组件13=奖励侧组件13。B若对所有捕宠点开放，会跳过守卫；助手保持严格不能阻止玩家随后走到仙人正常交奖，须明确裁定。
- 柏克尔Lv1(47,54)组件32，入口组件1，领奖组件12：属于原迷宫战前房间，不需终战。A生产GameScene原门→迷宫步行已0fail通过，无直接Session成功fixture。
- 隔离真实Backend逐点从1000 report_position：梦幻44条全拒绝，矿山6F七条全接受，其他实际目标接受。TimePassage在origin==target直接放行，洞内跨组件旧捕宠瞬移目前是潜在绕关；没有统一权威拦截。此处仅记录，不新增许可。

## 全部Lv1及补充目标

|名称/template|map / cell / area|实际门关系|当前跨图直达|A候选门外点|
|---|---|---|---|---|
|柏克尔65|41 / (47,54) / 408|时间门后，迷宫战前|拒绝|400(99,119)晨门旁；按时段选择原门|
|兰贝鲁斯332|10702 / (22,26) / 243|原楼梯可达，非守卫后|接受|保留现点|
|柯洛加斯83|10704 / (24,24) / 245|原楼梯可达，非守卫后|接受|保留现点|
|奇卡宝斯233|31806 / (5,7) / 362|矿工消费2527票门后|接受|31805(22,5)原票门邻格|
|卡卡金宝234（非原版补充）|31806 / (5,7) / 362|同上|接受|同上|
|奥卡洛斯301|31806 / (37,37) / 363|同上|接受|同上|

## 逐链组件排除

- 梦德11101–11107：口令100(443,127)→11101(33,29)，末层悟唐守卫；当前Lv1/rare/实际catch_plan均0。
- 强恩20601–20608：四至六楼口令、七楼守卫；当前Lv1/rare/实际catch_plan均0。
- 萨顿10701–10705：10条catch_plan，含2条Lv1。原碰撞、ground、三NPC占格、门户构建组件图；从10701(76,67)可达10701/1、10702/1、10703/1、10704/1、10704/2、10705/1、10705/5。全部捕宠点均可达，无须移除守卫或战斗。10705捕宠点在组件5，不能按整张五楼粗判守卫后。证据burkel-components.py/.log。
- 矿山31801–31806：1–4楼8条在票门前；5楼无普通安全索引；6楼7条（含3个Lv1）在票门后。原入口是NPC交易；普通report_position现接受6F直达。正常关卡仍消费2527。
- 龙洞20801–20807：1–6楼18条普通catch_plan，Lv1/rare均0；七楼三玉门后无捕宠点。取玉组requires_item2505已被普通地点算法排除；表中为普通三人龙，不能按全洞粗判三玉门后。
- 马祖118–122：120(19,15)原等级>49且禁止组队门→122(6,5)，门后118/119/122；当前Lv1/rare/catch_plan均0。
- 金布伊：按manifest全部37张地图（800–851子集、831、2020、4020）查询，问答/猜拳隔墙门后当前Lv1/rare/catch_plan均0。

## 复核证据

- `/private/tmp/burkel-all-catch-plans.json`：真实生产catch_plan全量枚举、Backend逐点返回和Dream组件。
- `/private/tmp/burkel-components.py`、`/private/tmp/burkel-components.log`：萨顿碰撞组件与原门户可达图。
- `/private/tmp/burkel-navigation-before.log`：原套件2fail复现，其余Lv1断言保留。
- `/private/tmp/burkel-original-route.log`：A生产步行已0fail通过。
- 源地图及C/Scripts SHA见对应`tools/*_quest_sources.json`，不宣称历史binary。

## 实际捕宠目标完整表

下表合并同格的物种；列的是现有便利目标，不代表B已经授权。

|map / area / cell|名称(template,等级)|门关系|跨图report|
|---|---|---|---|
|41 / 406 / (22, 8)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|41 / 407 / (7, 23)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|41 / 408 / (47, 54)|柏克尔(65, Lv1-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|41 / 409 / (55, 46)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|41 / 410 / (9, 40)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|41 / 411 / (25, 55)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|41 / 412 / (41, 10)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|41 / 413 / (58, 27)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|41 / 414 / (11, 56)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time / pre-final maze|False|
|41 / 415 / (59, 11)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time / pre-final maze|False|
|41 / 416 / (34, 35)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time + final guard|False|
|42 / 417 / (22, 8)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|42 / 418 / (7, 23)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|42 / 419 / (47, 54)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|42 / 420 / (55, 46)|柏克尔(65, Lv40-42); 凯比特(114, Lv40-42)|time / pre-final maze|False|
|42 / 421 / (9, 41)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|42 / 422 / (25, 55)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|42 / 423 / (41, 10)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|42 / 424 / (58, 27)|特洛昆(63, Lv40-42); 鲁尼帖斯(74, Lv40-42)|time / pre-final maze|False|
|42 / 425 / (10, 57)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time / pre-final maze|False|
|42 / 426 / (57, 13)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time / pre-final maze|False|
|42 / 427 / (34, 35)|呼拔拔(72, Lv40-42); 卡比特(111, Lv40-42)|time + final guard|False|
|10701 / 242 / (41, 39)|柯洛加斯(83, Lv25-28); 兰贝鲁斯(332, Lv25-28)|ordinary reachable|True|
|10702 / 243 / (22, 26)|柯洛加斯(83, Lv25-28); 兰贝鲁斯(332, Lv1-30)|ordinary reachable|True|
|10703 / 244 / (35, 41)|柯洛加斯(83, Lv25-28); 兰贝鲁斯(332, Lv25-28)|ordinary reachable|True|
|10704 / 245 / (24, 24)|柯洛加斯(83, Lv1-30); 兰贝鲁斯(332, Lv27-30)|ordinary reachable|True|
|10705 / 246 / (39, 38)|柯洛加斯(83, Lv25-28); 兰贝鲁斯(332, Lv25-28)|ordinary reachable|True|
|20801 / 258 / (33, 33)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|20802 / 259 / (25, 24)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|20803 / 260 / (22, 26)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|20804 / 261 / (27, 26)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|20805 / 262 / (24, 24)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|20806 / 263 / (22, 22)|邦洛洛克斯(331, Lv25-28); 兰贝鲁斯(332, Lv26-29); 可利多洛斯(333, Lv27-30)|before jewel gate|True|
|31801 / 356 / (22, 22)|卡克尔(181, Lv50-53); 卡拉卡利(184, Lv50-53)|ordinary reachable|True|
|31802 / 357 / (24, 24)|卡克尔(181, Lv50-53); 卡拉卡利(184, Lv50-53)|ordinary reachable|True|
|31803 / 358 / (24, 24)|卡克尔(181, Lv53-55); 卡拉卡利(184, Lv53-55)|ordinary reachable|True|
|31804 / 359 / (21, 27)|卡克尔(181, Lv53-55); 卡拉卡利(184, Lv53-55)|ordinary reachable|True|
|31806 / 361 / (21, 24)|奇卡宝斯(233, Lv60-63); 奥卡洛斯(301, Lv60-63)|ticket|True|
|31806 / 362 / (5, 7)|奇卡宝斯(233, Lv1-63); 卡卡金宝(234, Lv1-1); 奥卡洛斯(301, Lv60-63)|ticket|True|
|31806 / 363 / (37, 37)|奇卡宝斯(233, Lv60-63); 奥卡洛斯(301, Lv1-63)|ticket|True|

Input SHA256:

- `client/data/level-one-spots.json`: `bdc8163b70f60dd35d27d1cf844149269bbe2048e621eefd0e4b693121b98b12`
- `client/data/training-spots.json`: `a7190da3d93e570a7ecc9bf6b74cebba0b133fff2ead85cd3bd2338f3bbd01d4`
- `client/data/rare-encounters.json`: `efb391864412f6049ebd83dca8bfb9b96a2cae1231b4675c874a913ed12f020c`
- `client/assets/legacy/world/manifest.json`: `e6a60f483627255e96fb246789dccc2b7f0dc6e1ef3854f351986abd9bace265`
- `client/assets/legacy/encounters/catalog.json`: `3096139ff86059901cc6c0f9f56cd81d42bb9edc81267458243555e13c8e36eb`

## A实际路线验收完成

原独立探针`burkel_original_route_test.gd`：0 failures，无SCRIPT ERROR；该路线现合入`lv1_hunt_navigation_test.gd`及`tests/support/dream_walking_route.gd`，无需注册重复suite，未改玩法。

生产GameScene通过地图UI去400(99,119)门外；真实走到M门(98,119)，server hour930固定时钟边界→41(11,8)。逐步走原传送格：

1. (8,14)→(56,25)
2. (56,29)→(56,44)
3. 真实先走离(55,44)解除原arrival_lock，再踩(56,44)→(61,59)
4. (61,55)→(45,55)
5. 真实步行到(47,54)，UI选择柏克尔65/Lv1，开始找宠，Backend.automation.hunt_running=true。

此处证明开始权威找宠，不冒称已经捕获；日志在关闭菜单时遇敌0组。原门与迷宫没有任何Session位置伪造、save修改或终战跳过。普通目标(34,35)不在此战前组件。

## 测试驱动与生产路径规划的范围

测试按原portal组件图选择门序列，再用现有`travel_router._path_to`选相邻路点，逐点调用生产`walk_to`并等待移动结束；不直接给`game.path`赋值。最后一步等待实际原传送落点，到达锁仍通过真实走离/重踩解除。

这验证的是生产移动、时间门、原传送与权威找宠，不宣称普通`walk_to`会自动规划整座迷宫。`walk_to`本身只对当前地图调用navigation.get_id_path；router的路径选择另会暂时封住非目标传送格以避免误踩。任务测试选择路点属于测试驱动，不是新玩家自动寻路功能。

## 后续权威修复

本报告的运行结果固定于4854c86。随后获授权修复41/42同图跨组件报告，细节见[dream-same-map-passage.md](dream-same-map-passage.md)；其他门的限制及未裁定捕宠便利不因此改变。
