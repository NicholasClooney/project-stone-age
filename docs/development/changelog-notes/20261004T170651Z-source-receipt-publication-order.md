---
subject: "fix(quest-auto): prepare source receipts before queued snapshots"
title: "修正原任务地图确认的发布顺序"
---

- 开发中尚未开放的金布伊自动任务：原服务传送后，等待地图资源加载时不再因后续旧快照丢失位置确认凭据。
- 保存后取消仍保留原已提交位置；旧连接或已失效任务不能借排队凭据继续。公开任务入口仍未开放。
