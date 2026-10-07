---
subject: "chore(server): stage the private Start journal writer"
title: "开发准备：尚未接入的 Start 意图记录写入器"
---

- 新增仅供后端内部验证的 Start journal 写入器与独立故障测试，没有生产 caller，不改变玩家开始任务的行为。
- 仅在现有 JSON profile 边界验证 owner、新 run、current 与未决尝试的精确变化；不声称任意 native 容器的完整类型等价。
- 分开核对双次物理写入、主档与备份及临时文件观察、W1 内存安装和 wrapper 返回；W1 已落盘后 W2 失败不假回滚。
- Session 每次写入后的三次读回是旧路径上的连续观察，并非逐读 CAS；模块外围的状态校验不能外推为跨文件原子保证。
- 尚无 Start ACK、首票私有授权 cap、Hub、恢复、购买接线；没有启用自动购票，也不提供跨文件原子提交保证。
