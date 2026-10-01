---
subject: "fix(client): let queued 后台搜宠 hits raise the threshold at once"
title: "排队中的宠物也抬高门槛"
---

- 后台搜宠排队中的宠物现在也算进「最高」：排进一只更好的，门槛马上提高，后面只收能超过它的，不再一直排进一堆稍差的。
- 门槛提高时，排队中不再够格的会立刻放弃，信息框只记一行汇总，不再逐条刷屏。
