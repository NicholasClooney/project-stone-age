---
subject: "fix(ui): preserve quest helper window actions during refresh"
title: "任务助手刷新时保留窗口操作按钮"
---

- 修复项目便利功能“任务助手”在后台状态刷新时重新创建固定按钮、可能丢失点击的问题；自动任务设置、关闭和最小化按钮现在保持有效。
- 进入设置页时隐藏既有设置入口，返回任务助手后恢复；任务详情和服务端状态继续正常刷新。
