---
subject: "fix(import): encode portable original NPC image filenames"
title: "修复多实例任务图片的跨平台路径"
---

- 原任务人物图片改用可逆的 UTF-8 十六进制文件名，地图实例中的冒号、斜杠及大小写不会在 Windows 路径中产生非法名称或撞名。
- 逻辑人物编号保持不变；合入后须重新导入任务资产，catalog 会统一指向新文件名，旧图片不自动删除。
