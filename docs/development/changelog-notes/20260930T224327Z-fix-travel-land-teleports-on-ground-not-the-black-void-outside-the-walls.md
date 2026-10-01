---
subject: "fix(travel): land teleports on ground, not the black void outside the walls"
title: "传送不再落到墙外黑地"
---

- 刷怪传送、地图导航和宠物大全「瞬移去抓」有 27 个落点在原版墙外看不见的黑色空地上（例如五十年前波拉岛 547,515：只画出人物，四周全黑）。现在只选有地面的格子，传送检查也跳过这类格子。
