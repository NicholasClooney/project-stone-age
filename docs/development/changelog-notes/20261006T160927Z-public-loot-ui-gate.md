---
subject: "fix(ui): gate public loot start on server capability"
title: "限时刷物入口受服务端能力控制"
---

- 服务器未明确开放限时刷物能力时，任务菜单不显示开始入口；服务端状态与连接变化会更新入口资格和提示。
- 限时刷物目前仍未开放，界面不会自行创建运行状态，也不会把迟到的旧回包当作当前启动成功。
