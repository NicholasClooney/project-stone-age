# 同图项目移动权威同步

旧 `dev_map_overview.teleport_near` 同图分支直接改 GameScene 坐标后 checkpoint，从未 report_position。因此新增捕宠位置复核会拒绝画面已到、服务器未到的普通 Lv1 点。

现在调用专用 `project_position`，服务器验证同图、整数坐标、地图碰撞及 NPC 占位后沿原 report 检查；内部来源固定 project，移除导航 receipt，不能由客户端声明 walk/party 获得原路记录。客户端等待成功响应及权威 position 被场景应用，才 checkpoint/关闭地图；失败保持旧坐标并说明。公开入口前移动仍允许，保护区域的项目移动只撤资格。

定向：`project_position_authority_test` 原迷宫连续到守卫后验隔墙拒绝且保原资格、同组件相邻项目移动撤资格、伪造坐标启捕拒绝、越界/占位/跨图拒绝，0 failures。日志 `/private/tmp/project-position-authority.log`。

并集 `lv1_hunt_navigation_test` 保全部原 found/render/enabled 断言及真实开始捕宠，0 failures（`/private/tmp/reviewed-lv1-navigation.log`）。该套件还含单独捕宠 UI 片的目标选择与异步等待改动，将随捕宠片提交；本提交只改普通地图同步。
