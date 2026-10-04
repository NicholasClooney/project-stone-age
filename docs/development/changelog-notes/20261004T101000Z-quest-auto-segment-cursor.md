---
subject: "fix(quests): prepare bounded segment cursors and complete fast-mode receipts"
title: "补充分段移动的服务端校验底座"
---
- 服务端增加分段游标，保留完整原路校验资料，每次只接受当前待执行格，位置消息仅可包含已执行前缀。
- B/C 位置回执要求完整任务、步骤、版本和段身份，取消、断线及遇敌会清除待执行尾段；保留 A 模式既有兼容协议。
- 这是尚未启用的核心接点；当前实际模式仍只有 A，B/C 需等待真实导航、遇敌和重连并集验收。
