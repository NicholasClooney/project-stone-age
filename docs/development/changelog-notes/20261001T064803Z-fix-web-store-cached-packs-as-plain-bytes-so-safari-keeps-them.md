---
subject: "fix(web): store cached packs as plain bytes so Safari keeps them"
title: "Safari 刷新后不用再重新下载素材"
---

- 网页版：缓存的素材包改为直接存字节数据，不再存 Blob。Safari 存进去的 Blob 刷新后会读不回来，导致每次刷新都重新下载音乐和起始地图。同时向浏览器申请持久存储，减少被自动清理。
