# 成人礼助手／自动原路整合

用户最终通用要求取代旧“助手绕过等级门”的项目便利。仅事件4局部修改，原REQUEST的LV>0条件没有伪改为30；30来自10202(31,13)的真实原门。入口绑定genout/wpm_10202_31_13，原Warp至10204(2,6)，原源及政策SHA审计见quest-legitimate-arrival.md成人节。

## 产品行为

- helper.destination：原成人NPC及两种导航mode，无合法通道route时只给10202门外安全点；已沿原路入场时只允许NPC可谈范围的当前格。远处拒绝，不移动也不撤资格。其它链dispatch和容量摘要保留。
- adult_walk_destination是服务器纯几何目标，供连续走路计算；不签位置、不授资格、不供客户端命令直接调用。OriginalRouteDriver测试适配由arrival owner另片负责。
- quest_auto：先项目移动到公开入口前30,13，真实相邻走至31,13，重核原portal目标/等级字段及生产check_passage，才执行原portal步进入2,6；随后每格原通道走路/原遇敌/原交易。未知portal、缺图或未取得route停止，不创造替代入口。
- 自动任务启动时等级低于30明确拒绝；load_resume不反序列化route，恢复真实战斗后按新的空资格重新进门。没有修改save格式、战斗RNG、医师并行旗标或其它自动任务。
- 客户端JOB_MAPS只把成人项由[10204]改[10202,10204]，先下载公开门外地图；其余job不变。

## 验证与依赖

基础完整并集见reviewed-capture-arrival-handoff.md。成人政策37a768c（本槽fdcf5e7）、成人去重test df1a652（本槽d89489d）、party源5161a11（本槽57a6437）已取，未夹带火链其它依赖或dirty。party修只影响模块，保留地图项目命令对队长/队员的既有拒绝。

- original_adult_quest_test：原低级门拒绝、助手只能门外、真实30级入口、远处拒绝不撤route、十五空格/十五UID仪玉、原单次END4、连续往返步数>300，随机遇敌开/关两种真实自动结算，0 failures。/private/tmp/strict-adult-quest.log。
- adult_entry_boundary_test（新增注册）：精确预载集合、rawNPC/旧step两mode、低级check_passage/report均拒，auto明确等级30且不启动，道具/旗标逐项不变，0 failures。/private/tmp/strict-adult-entry-boundary.log。
- original_adult_ui_test：真实remote GameScene，原helper只到门外，生产walk_to走原门；现有router仅计算待点击相邻路点，每一步由生产walk_to推进。远程原对话、自动任务真遇敌与继续、停止、断线停止均通过，0 failures。/private/tmp/strict-adult-ui.log。本次headless，不声称新390像素图或整通道一次点击自动寻路。
- adult_quest_resume_test：保原真实battle turn/RNG/troop与未完成事务、重启续行、旧checkpoint拒重放、v5/v6设备耐久、延迟/伪造receipt、手动/组队/停机/savefail停止，0 failures。/private/tmp/strict-adult-resume.log。新原入口可能在首NPC接取前遇敌，测试角色按真实ProfileHub流程先保存初始Lv30状态，不能依赖首NPC交易偶然产生save。
- /private/tmp/strict-adult-preload.log对实际生产pack plan核10202与10204均有有效pack归属，其余预载任务集合原样。该单行预载没有重复跑已绿UI。

共享brothers_golden_quests_test仅adult(b)改成真实complete_adult，待arrival owner独立driver几何接口兼容片并集后跑受影响继承者一次；不把尚待该片的共享fixture回归称为已完成。所有其它任务policy仍按owner逐片审核；固定NPC组队战没有开放。无full、无真实save/live操作。原图与原物品导入无需变化，部署照常重建Web。
