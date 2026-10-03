---
subject: "fix(world): refresh quest residents in one pass"
title: "减少地图与任务指引的人物更新开销"
---
- 减少切换地图、更新任务指引和创建角色时重复整理任务人物带来的等待。
- 保留原有居民顺序，以及每名角色独立的任务人物隐藏、移动和区域出生位置。
