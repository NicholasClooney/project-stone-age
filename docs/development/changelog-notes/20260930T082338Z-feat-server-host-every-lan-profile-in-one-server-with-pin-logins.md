---
subject: "feat(server): host every LAN profile in one server with PIN logins"
title: "局域网多人：一个服务器带多个角色"
---

- 开发者功能：用 scripts/relaunch.sh --accounts=user://lan/accounts.json 启动，一个服务器、一个地址就能让局域网里每个人玩自己的角色；每个角色各有存档、自动战斗、找宠、宠物记录和重启恢复，互不干扰，也只收到自己角色的更新。
- 账号用 scripts/accounts.sh 管理（add、pin、admin、create、remove、list）：名字加 4 到 8 位 PIN，PIN 只以加盐哈希保存；连续输错 5 次锁 5 分钟。可以把现有的单人存档加为自己的角色（--save=user://single-player.json --admin）。
- 只有管理员角色能用 GM、立即脱战、战斗测试和本机极速模式线程数；第一个角色默认是管理员。练级助手的经验倍率仍是普通设置。
- 几个角色同时挂机时平分服务器每帧的计算时间；本机极速模式每个角色各算一份线程。每次打开存档先在 backups 文件夹存一份带日期的备份（保留最近 5 份）；服务器正常停止时每个角色都写下恢复文件，重启后不用登录就接着跑。
- 登录画面在客户端还没有（见下一条）；不加 --accounts 时和以前完全一样（单人存档，不用登录），每人一个服务器的 scripts/profiles.sh 仍可使用。
