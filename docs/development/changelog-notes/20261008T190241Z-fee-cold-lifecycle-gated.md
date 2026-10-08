---
subject: "chore(server): stage gated fee cold-load retirement"
title: "内部：收费冷加载收尾入口仍默认关闭"
---

- 新增默认关闭的收费冷加载内部入口：绑定存档路径后，依次经过可信 baseline、私有 recovered-close 和独立精确 sidecar 退休。尚未开放新收费功能、Start 资格、首票购买或 runner 付款；legacy 与纯刷物路径保持原行为。
- 仅真实 writer 内部核验成功产生下一步私有权限，公开诊断 ok 不授写权。共享 exact-retire 增加四处 cold_call 接点；不带 cold_call 的普通 Stop 由既有定向回归验证。
- mixed/foreign sidecar 不删除、不执行；保留非收费残余字段会暂缓该 Backend 的自动重启记录更新，手动 profile 保存仍可用。pending 诊断仅在内存中，既有 current/tombstone 与实际 sidecar 才是持久义务记录，不增加 schema 或 WAL。
- 合同限 JSON profile；Session 三读仍是旧路径连续观察，而非逐读 CAS，无跨文件原子保证。非幂等 closed 状态继续保留待处理；收费冷收尾失败不阻登录，目标存档打不开仍保留旧连接语义。
- 两套新测试与十六套定向回归均完成 check-only/runtime，自然退出且源码/引擎锁不变。Hub 验收组合覆盖真实 open/logout 和内部 switch 函数，不声称完整认证 WebSocket 切换。未运行 full/import、未注册新套或验证渲染像素；Start 与 Hub 离开接线仍待后续分片。
