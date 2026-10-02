---
subject: "fix(quests): keep Munde navigation destinations in the current component"
title: "梦德导航落点不跨越守卫墙"
---

- 梦德导航的瞬移邻格与步行起点均只从角色当前可达区域选择，防止唐、悟位于墙边时因邻格顺序而跨越原守卫墙。
- 地图载入失败或胜利落点不可达时，族长步骤保持未解锁；不会把两个无效区域误判为已经战胜守卫。
