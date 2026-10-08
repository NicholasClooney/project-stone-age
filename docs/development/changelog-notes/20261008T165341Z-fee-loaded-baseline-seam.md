---
subject: "chore(server): add trusted-load fee baseline seam"
title: "内部：收费加载凭据与精确基线写入（尚未接入执行）"
---

- 真实成功 load 仅产生私有收费凭据，并绑定重建后的刷物 timer；新增精确 baseline writer 与独立故障测试，但没有生产 baseline 执行 caller，不注册测试或开放收费能力，已上线刷物行为保持。
- 仅承诺 JSON profile 边界；Session writer 后的主备/tmp 三读是旧路径连续观察，不是逐读 CAS。模块外层另核引用、完整值、路径、serial 与私有 claim，不保证跨文件原子，也不把 false/unknown 包装返回当作未发生物理写入。
- 无 B2b recovered-close、Start ACK/cap、Hub 接线或购票。后续 close 必须有独立私有 continuation，不能用返回值 ok 充当授权。
- 已知兼容限制：合法旧 fee profile 若在 Backend.snapshot 补可选仓库字段，baseline 会保守拒绝绑定，原 load 返回语义不变；B3 之前必须处理此项，不代表完整存档兼容。
- 新套实测 1209 checks、0 failures、87 fixture 全部到达，runtime wall 149.053 秒；四处有限阶段日志保留。此前 120 秒超时现场保留，不能将该旧窗记为通过。另十套批准的 fee/loot 定向回归全部自然通过；未运行 full、未渲染像素验收。
