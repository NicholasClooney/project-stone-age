---
subject: "fix(quests): accept signed peer ids for internal loot admission"
title: "修正内部刷物连接身份的断线判定（未开放）"
---

- 内部限时刷物只将 -1 视为断线标记，不再误拒绝 WebSocketPeer 的合法负数实例身份；原来源、运行身份、客户端及保存事务检查保持不变。
- 本片仅修正未开放刷物底座的身份契约，不新增公开入口，也不将非 -1 身份视为连接或账户认证。真实联网界面仍需独立并集验收。
