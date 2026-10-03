# 服务器合法到达接口接入

前置到达模块 `799d9cc` + 领奖离区修复 `7cbcc3b`。当前政策首片只保护梦幻41/42；不宣称全任务政策已完成。Backend 实例持有 `quest_arrival`，载入成功清空；记录不写 profile/save/resume。

所有 `automation.position_changed` 默认项目移动，只撤不授；普通 report、服务器逐格 walk、原脚本 script、内部 party 分别传可信来源。恢复捕宠位置和旧自动活动字段写入也经过项目来源。重复同坐标不清除记录。原同图 DreamPassage 和时间门检查仍在原处，不为捕宠改成通用豁免。

原固定战 begin 检查真实NPC/branch并生成私有上下文。个人成功原子save后排队胜Warp记录，真正 close_battle 发布 script Warp 才授到达。保存失败恢复完整pending、profile与原claims。资格失效不吞正常战果：仍按原slice/claim结算体力、药耗、经验、金币，仅跳过任务steal/隐藏/Warp；在候选claims副本扣留模块精确派生的专用物。完整原claim先检查索引、重复、敌死/未抓；不合法集合原样交Session拒绝，不会被过滤洗白。

实际固定NPC战在现生产Hub本来禁止组队，本片保留。真实普通party跟随由Hub服务端旧/新位置提供证据；模块还检查各成员自己的连续路线，绝不复制队长资格。本片不修改party_battles或party_settlement。

服务器捕宠命令 `reviewed_hunt_travel` 从实际PetEncyclopedia.catch_plan与审核表交叉派生精确51目标（梦幻44、矿6F7），重核真实图/碰撞/区域/非portal非NPC。客户端不提供可信cell，额外grant/party字段无效；busy、组队、未知模板/区域拒绝。项目捕宠移动绝不授任务资格。UI接入是后续提交；不能仅凭本片宣称真实NPC领奖防绕已经接通，最终事务guard由风owner独立接。

自动活动启动的坐标必须匹配已有服务器位置；未知初始位置不能直接声称位于三张捕宠保护图。该重核暴露旧dev_map_overview同图瞬移没有report的问题，单独同步修复提交解决，不能放宽位置授权来掩盖。

`quest_arrival_backend_test` 通过生产Backend.handle逐格遍历原迷宫（独立碰撞oracle），真十敌战、savefail多次重试、真实胜Warp、原出口离奖区失去mark、捕宠离开/重回不授、近处helper原地/远处拒绝且保route、失效战普通结算可关窗、精确claim过滤与畸形claim保留。`reviewed_hunt_travel_test` 51实际点、伪坐标/模板/区域/party及普通raw跨墙拒绝通过。日志 `/private/tmp/quest-arrival-backend.log`、`/private/tmp/reviewed-hunt-travel.log`。均定向，不跑full。
