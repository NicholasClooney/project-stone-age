---
subject: "fix(lan): guard remote player node lifetimes"
title: "联机换图后其他玩家正常显示与选择"
---

- 联机地图重建后，其他玩家的显示节点可安全恢复；点击人物仍可查看信息卡片。
- 忽略已释放、等待释放或属于旧地图的人物节点，避免换图、断线及界面销毁后的脚本错误。
