---
subject: "chore(server): normalize exact loaded storage defaults"
title: "内部：收费加载仅接纳精确仓库默认字段（尚未接入执行）"
---

- 在真实成功 load receipt 的 snapshot 前后加入私有一次性核验：仓库三字段全缺时只允许空数组、空字典和整数零；全有时完整保值。其它字段、类型、引用或归属变化只拒绝收费权限，不改变原 load 返回、snapshot 效果及磁盘行为。
- 分开保存原 loader 的实际 profile 字节与规范化 baseline 目标；已发生的刷物冷退休写盘保留原证据，不移动原写盘，也不无条件刷新 receipt。仅覆盖 JSON profile 的这三字段兼容，其它 snapshot 迁移仍保守拒绝。
- 没有新增收费执行 caller、Start/Hub 接线、购买或功能开放；B2b 私有 continuation、旧 Stop/B1、loot writer 原样保持。Session 三读仍是旧路径连续观察，不是逐读 CAS，无跨文件原子保证。
- B2a 的 snapshot_migration 从旧拒绝组移入已有完整成功 oracle，87 fixture 不变；这是明确的测试兼容迁移，不是旧拒绝断言仍通过。新套实测 377/0、32 fixture、33 次真实 load、46.149 秒；迁移后的 B2a 为 1214/0，另 B2b 两套与六套 fee 定向回归全部通过。
- 十套均 check-only 后 runtime、自然退出且双日志干净，源码/引擎前后锁一致；成功失败盘与历史超时证据保留。未运行 full/import/额外 suite，未验证渲染像素。
