---
subject: "fix(navigation): synchronize same-map project travel with authority"
title: "同图地图瞬移先同步服务器位置"
---
- 地图快捷移动同图落点先由服务器审核，再等待场景跟随权威坐标后开放捕宠；不再只有客户端画面移动。
- 项目移动不能冒充原路线步行，同组件移动也撤销任务到达记录；原梦幻隔墙、时间门和人物占位检查继续生效。
- 捕宠专用审核点仍使用独立入口，普通地图移动不借用该许可。
