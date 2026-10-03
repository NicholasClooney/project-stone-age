---
subject: "fix(quests): project only matching NPC source scripts"
title: "减少任务步骤读取中的全目录复制"
---

- 十二组任务助手读取指定原脚本时，仅投影该脚本对应的 NPC，减少移动和任务状态更新时的重复目录处理。
- 保留同源多图、个人 NPC 状态、原分支顺序及选择条件；任务步骤、路线资格、奖励和随机规则不变。
