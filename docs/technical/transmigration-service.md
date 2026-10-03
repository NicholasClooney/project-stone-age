# 精灵王事务服务

服务只接受目录中已启用、精确绑定的 `777/ten.arg@32021:31:28`。生产descriptor仍关闭；本片不改变激活表或117监狱出口。`quest_talk`返回顶层`transmigration`预览，协议三命令同冻结v1合同。

服务内私有pending绑定真实NPC、当前profile前态、Backend revision、Arrival action proof、UID选择与独立奖励RNG种子。旧token不能确认或取消新preview。预览不公开成长随机值；同前态换选保持seed。WS服务器注入的`_quest_connection`字段仅允许经过传输，不参与授予任何权限；其它额外业务字段拒绝。

确认再次核活动、组队、距离、历史、前态/revision和私有到达proof，随后不await直接一次保存候选。失败保留原profile、proof、UID与候选；成功保存已含返村位置和transaction_id，才消费proof、清对应任务冷却/NpcWarp记录与助手缓存、发布一次返村与profile。TimeMan图文、独立出生点、仓库和旧战斗记录不粗暴清空。

新增奖励宠`favorite=false`在候选中就完整写入，避免首次snapshot才补字段造成内存与本次磁盘不一致。读回断言以Session原有整数化规则比较全部字段：源JSON整数float变成存档整数不是资产变动。

定向suite `transmigration_service_test`通过原门与原portal路径，真正打五敌/十敌；两次守卫分别失败写盘、再成功写盘、close真实Warp后才获stage；最后门后两设备连接真实WebSocket服务。测试无坐标grant、无伪proof。覆盖顶层talk预览、UID重新预览、迟到cancel、旧confirm、两次savefail保同candidate/proof、成功一次返村、另一设备重放和新Backend读回。

此处是服务器与WebSocket事务验收，渲染像素及生产world资源导入由UI/C后续实际并集闭环；不声称全部原出口已支持。监狱已裁项目方案B：收min(gold,10)，零币沿原内部Warp；具体117/110服务由独立owner实现，本片仍不激活。

补充真实双设备负例：同token混入客户端新转数/seed/base_stats整请求拒绝；错误模板UID不替换有效preview；另一设备通过真实gm_grant_points改变profile/revision后旧confirm拒绝，不扣宠。新增日志`/private/tmp/stage-three-service-negative.log`，连同原两战/savefail/restart矩阵0fail。
