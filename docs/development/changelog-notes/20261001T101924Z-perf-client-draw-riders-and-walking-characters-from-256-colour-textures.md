---
subject: "perf(client): draw riders and walking characters from 256-colour textures"
title: "骑宠与人物行走图显存减到四分之一"
---

- 骑宠（野外和战斗中的骑乘造型）和玩家人物的行走图也改为 256 色调色板贴图，显存只有原来的四分之一（萨姆吉尔村里自己的人物图约 1.3 MB 降到 0.3 MB），画面逐像素不变。
- 网页版：骑宠和人物资源包改为直接下载原始 256 色 PNG。开发者性能数据（window.stoneAge）新增按类别的贴图内存。
