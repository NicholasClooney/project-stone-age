---
subject: "fix(client): keep the restart-resume file current and shut down on request"
title: "服务器被强行结束也能接着找宠"
---

- 「重启后自动恢复」开着时，找宠流程、单独筛选或自动练级运行期间服务器一直把进度写在恢复文件里：流程一有进展（换阶段、抓到、开始练级、排队变化）马上写，否则每 10 秒写一次，每次先存档。服务器被强行结束（包括断电式的强杀）后重启也能接着跑，最多重找最后 10 秒的组。运行停下时恢复文件随即删除。
- 以前的修正并没有生效：服务器收到 TERM 时不会走正常退出，恢复文件写不出来，重启后没有恢复。
- 开发者：新增 scripts/stop-server.sh，让服务器自己存档、写恢复文件后退出（停止记录写「暂停」），30 秒没关掉才改用 TERM；scripts/relaunch.sh 重启和 Ctrl-C 都用它。
