---
subject: "fix(navigation): guard project travel callbacks and party membership"
title: "地图移动拒绝组队并取消过期回包"
---
- 地图项目移动对队长与队员均要求先离队，不能因为新命令名称绕过组队限制。
- 等待移动回包时关闭、重开或切换地图会取消旧请求的界面收尾；另一设备改位不会让旧请求保存错误坐标或关闭后来面板。
- 场景或提示控件释放后，迟到回包和等待协程不再访问已释放对象。
