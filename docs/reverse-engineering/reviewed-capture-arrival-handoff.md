# 门后捕宠与合法领奖整合

## 最终决定

用户最终授权：保留全部实际受新门阻挡的catch_plan原坐标。梦幻41/42各22条、矿山31806七条，共51个map/area/template组合；包括两个34,35领奖组件捕宠点。该项目便利仅专用reviewed_hunt_travel可用，UI明确“项目便利，绕过原版门”。列表在client/data/reviewed-hunt-travel.json，服务器再次从实际图/区域/catch_plan派生并验证目标，不接受客户端cell或grant。

任务资格是项目补充，不是原save旗标。梦幻采用统一quest_legitimate_arrival，真终战受审上下文、个人成功保存及真实原Warp三者齐全才激活；保存失败保冻结pending/roll可重试。抓宠传入不授予，项目移动、原路离开领奖组件、服务器重启失效；NPC最终transact再验。一次合法访问不因领取单次谢礼而额外消耗资格。原前三轮仍第三次END34、原branch4仍无限重复，不混同两项规则。

## 精确依赖

基础来源799d9cc、7cbcc3b（本槽5099a3c、502b23a）；backend/brothers/Hub/捕宠命令b2c9ad1；普通NPC最终事务3b5790a（本槽3d0b549）；arrival风/梦德增量21acb34（本槽dc77aec）；服务身份372481b（本槽f8ab156）。普通地图同步独立7e5a06f，生命周期与party独立2224d3c。只取原始hash或本槽等价之一，不能重复拷底座。成人37a768c/df1a652另片接入，不是本捕宠片宣称已完成范围。全任务policy尚在逐链交付。

## 定向证据

- reviewed_hunt_travel_test：全部51精确派生、伪cell/物种/area/party、普通report不能借许可，0 failures，/private/tmp/reviewed-hunt-travel.log。
- reviewed_hunt_arrival_remote_test（新增注册）：两个真实socket，41/42抓宠进领奖区后真仙人拒绝且flags/items不变；真十敌终战保存失败/重复close/成功重试，第二设备抓宠重入拒旧token；重新真终战后成功原交付，重启无到达资格。0 failures，/private/tmp/reviewed-hunt-arrival-remote.log。
- lv1_hunt_navigation_test：保全部原found/render/enabled及真开始捕宠断言，审核点经宠物大全专用入口，普通点经地图权威同步；0 failures，/private/tmp/reviewed-lv1-navigation-final.log。
- dream_catch_boundary_test：生产remote GameScene、390×844静音离屏，实际hover/鼠标点击41/42捕宠按钮，到权威34,35、正确物种并真点击开始/停止，普通跨墙仍拒绝；0 failures且无SCRIPT ERROR，/private/tmp/reviewed-capture-ui-final.log。四张/private/tmp/reviewed-capture-shots/*.png逐张view_image；既有自动抓宠面板在窄屏仍部分横向裁切，本片未改其布局，目标/位置与开始按钮可见且可点。
- 原三轮dream_cave_quest_test与重复奖dream_repeat_reward_test改为真实原入口/逐格迷宫/战斗/保存Warp，不再直接放领奖区授资格；2/2，/private/tmp/reviewed-natural-dream-tests.log。独立高属性战斗fixture不替代敌队、战斗或结算。
- 更新后的dream_cave_ui_test与dream_repeat_ui_test以真实Backend路线准备，原UI点击/事务2/2通过，/private/tmp/reviewed-dream-ui-route-tests.log；此批headless只计逻辑，不计新像素证据。
- 地图生命周期与party旅行拒绝见project-position-sync.md。普通party合法路线另由arrival owner修模块并验收；固定NPC战仍不支持组队，不伪称可玩party终战。

## 生产资源与导入

本片只新增代码和已审核JSON，不改原资产 importer；重复奖励完整物品导入命令仍见dream-repeat-reward-handoff.md，world/battle art无需重导。生产Web preset include_filter=data/*.json实际导出build/reviewed-pack-proof/client.pck，再从空项目挂载读回res://data/reviewed-hunt-travel.json，targets=51：/private/tmp/reviewed-pack-export.log、/private/tmp/reviewed-pack-readback.log。部署须照常scripts/build-web.sh重建，不能仅更新按图asset packs而遗漏主PCK。

所有测试使用测试user目录；无full、live端口或真实save操作。截图、原资源与导出PCK不提交。
