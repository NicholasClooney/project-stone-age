---
subject: "chore(fees): stage gated lobby first-ticket purchase"
title: "内部：大厅首票购票链仍默认关闭"
---

- 内部准备：默认关闭的 job2/event44 大厅 adapter 只为一次显式 Start 准备原价单票；已有票不扣款且保持 manual_only。独立尝试双副本先落盘，再由同一候选扣金、通过原版装备入口生成真实票 UID 并记录购票事实。Start ACK 仅代表持久意图，不是扣款；本片没有入场消费、200/300 自动付款或开关开放。
- 临时决定：协调者“夜间决定，待用户确认”——只有新购票实际 I/O 已进入且读回仍 unknown 时，才对精确 owner/Session/path 及捕获 run 归属阻止保存。这是“手动 save 不阻”的唯一异常例外；通用保存于 snapshot 前拒绝，经原提示通道要求重新进入存档，拒绝次数仅为内存诊断。退出与切换仍可完成，不自动重载、合并或修盘。
- 同一夜间决定延伸：Session 共享物理候选入口新增默认空的私有守卫；生效时其它 writer 走原失败路径。原物理 writer 主体保留，但不声称整个 Session 零差异。真实 loader 仅有精确源文件与私有身份绑定的退休写盘例外；核准成功 load 才解除保护，失败 load、run 退休和 warm 缓存不能洗掉保护，不同后继不继承旧 hold。
- 权限限制：公开成功字段、ACK、重连或 continue 不产生购票资格，同 binding 去重；客户端资源包等待前的一次点击可在新 binding 首次发送，不保证跨进程 exactly-once。实际提交事实不被外包装 false 或旧 owner 后继抹去，失败和 unknown 不伪造 committed。购票 primary 可能比尝试 backup 更新，无跨文件原子保证。
- 验证说明：三套新测试与三十七套定向回归分窗通过。purchase/Hub 沿用生产、脚本及依赖同字节的前窗结果；本窗 cross 修正独立 JSON 数值字节 expected 后通过，再跑旧队列，全部旧 FAIL 与盘保留。新套使用真实 Accounts/Hub 同步入口、fixture 门和故障 hook；不冒称完整认证 WS。loot/转生跨 writer 覆盖直接 Session 事务，不等于完整玩法前置，held loot settlement 未独立构造验证。
- 边界说明：JSON profile 范围事实不声称设备私有；Session 旧路径连续观察不是逐读 Backend CAS，无 WAL、历史数组或 schema 扩展。父 writer 对照在候选环境执行；未注册新套、运行全量、导入、开启收费链或验证渲染像素。
