---
subject: "fix(client): don't judge a queued 后台搜宠 hit against itself"
title: "排队中的宠物不再和自己比较"
---

- 设为「最高 + n」时，新找到的最好一只不会被当成不够格放弃。
- 因门槛提高放弃的宠物也记入放生记录，带组号。
