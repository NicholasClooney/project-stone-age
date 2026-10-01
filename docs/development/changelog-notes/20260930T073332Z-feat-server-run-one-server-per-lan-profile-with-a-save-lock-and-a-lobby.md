---
subject: "feat(server): run one server per LAN profile with a save lock and a lobby"
title: "局域网多人档案：每人一个服务器和大厅页"
---

- 开发者功能：在 profiles.json 里列出角色（名字、端口、存档），用 scripts/profiles.sh start 为每个人各启动一个服务器，各玩各的角色；stop 全部停止，status 查看。单人用的 scripts/relaunch.sh 不变。
- 大厅页：打开 网页端口/lobby，列出这台电脑上的每个角色、是否在线，点「进入」就用该角色的服务器打开网页版。
- 存档锁：一个存档同时只能被一个服务器打开，第二个会拒绝启动并说明被哪个进程占用；进程已经不在时自动接管。
- 还没有登录：知道端口的人就能玩那个角色；大家也互相看不见，组队以后再做。
