---
subject: "chore(server): add private recovered fee close continuation"
title: "内部：收费冷加载私有收尾原语（尚未接入执行）"
---

- 只有精确 baseline 已匹配或真实写入并完整核验的成功出口产生私有、一次性 continuation；新增独立 recovered-close 原语，但没有生产执行 caller、命令注册或收费开放，也未接 Start ACK/cap、Hub、sidecar 执行或购买。
- 每次 Backend load 入口仅撤销内存权限；真实成功、失败 load 的原返回与磁盘行为保持。公开诊断 ok 不能生成、恢复或抹去内部权限。关闭仅改 fee journal，保留已加载的刷物退休账本、收益、金额和 UID。
- 第一次主档可证且 owner 当前时有限安装；后续 false、partial、unknown 不假回滚已落事实。仅承诺 JSON profile 边界；Session 主备/tmp 三读仍是旧路径连续观察，非逐读 CAS，无跨文件原子保证。closed+attempting 非幂等记录 hold，零写，不迁移 Session。
- 已知仓库字段兼容缺口仍在：snapshot 补可选仓库字段会让 baseline 保守拒绝绑定，B3 之前必须处理。旧 Stop/B1/loot writer、Session 与 Hub 未改，刷物开放不回退。
- 两新套实测 475 checks/0 failures/32 fixture（51.623 秒）及 1103/0/64 fixture（113.575 秒）；随后 B2a 和六套批准 fee 回归全部自然通过。九套均 check-only 后 runtime、双日志干净、前后源码与引擎锁一致。成功失败盘及原超时证据保留；未运行 full、未验证渲染像素。
