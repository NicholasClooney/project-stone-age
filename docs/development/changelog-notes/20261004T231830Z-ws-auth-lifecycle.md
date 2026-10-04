---
subject: "fix(network): retire websocket authentication callbacks safely"
title: "修复重连认证回调期间关闭连接的处理"
---

- 远程连接在认证回调中关闭或重新连接时，不再继续发送旧连接的已连接通知。
- 主动关闭立即撤销在线状态，并将旧连接未完成请求各返回一次离线结果；回调已建立新连接时，旧连接清理不会关闭新连接或发送过时的断线通知。
- 开发验证覆盖真实 WebSocket 回调重入与角色切换场景；此修复不开放刷物功能。
