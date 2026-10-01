---
subject: "fix(scripts): stop the backend with TERM so it saves and can resume"
title: "重启服务器时正常关机"
---

- 开发者用的重启脚本改为让服务器正常关机：先存档，再写下重启恢复文件，自动抓宠重启后能接着跑。以前服务器会被直接结束，恢复文件写不出来。
