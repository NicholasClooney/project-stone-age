---
subject: "fix(server): only prune rejects from the current hunt run"
title: "留前N只淘汰本轮未达标宠物"
---

- 自动找宠的「留前N」滚动淘汰只在本轮存入的未达标宠物中挑选，仓库里之前各轮留下的宠物不再被删除。
- 达标宠物存仓后不参与滚动淘汰，永不自动删除。
