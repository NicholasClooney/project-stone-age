---
subject: "fix(server): reconnect a client that stopped reading instead of dropping its updates"
title: "后台设备不再悄悄掉画面更新"
---

- 某台设备的网页在后台停止接收时，服务器原来会继续丢弃发给它的消息，回来后画面停在旧状态；现在会断开它，设备自动重连并重新同步。
