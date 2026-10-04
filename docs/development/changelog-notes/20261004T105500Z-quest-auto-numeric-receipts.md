---
subject: "fix(quests): normalize integer coordinates in movement receipts"
title: "修复自动任务跨图位置确认"
---
- 修复原地图数据中的整数浮点坐标与远程客户端整数确认不匹配，导致自动任务跨图后持续等待的问题。
- 坐标、位置序号和版本字段必须是有限数学整数；小数、布尔值和无效数值不能借规范化绕过原位置与完整任务身份核验。
