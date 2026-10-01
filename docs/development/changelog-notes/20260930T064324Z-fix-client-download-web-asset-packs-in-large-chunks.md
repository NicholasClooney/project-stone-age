---
subject: "fix(client): download web asset packs in large chunks"
title: "网页素材下载加快"
---

- 网页版下载素材包时每帧读 4 MB（以前 64 KB），核心素材在本机或局域网里一两秒就能下完，不再要七八秒。
