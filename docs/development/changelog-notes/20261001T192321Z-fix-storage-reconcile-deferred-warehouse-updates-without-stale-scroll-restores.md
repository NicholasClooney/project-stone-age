---
subject: "fix(storage): reconcile deferred warehouse updates without stale scroll restores"
title: "仓库实时更新与滚动修复"
---

- 宠物仓库的品种下拉菜单关闭后会补上期间收到的存取变化，数量、属性与操作保持同步。
- 仓库与宠物记录复用滚动区时不再延迟恢复旧位置，避免覆盖刚刚滚到顶部的位置。
