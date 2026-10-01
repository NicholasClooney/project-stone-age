---
subject: "fix(client): load maps as packed grids to cut memory use"
title: "地图占用内存大幅减少"
---

- 地图改为紧凑格式读取：在野外时内存少用约 150 到 250 MB（萨伊那斯地图 125 MB 降到约 7 MB，加鲁卡 196 MB 降到约 10 MB），切换地图时也不再出现内存高峰。网页版内存峰值随之少约 200 MB，地图素材包小了近一半。画面、行走、遇敌和自动寻路都和以前一样。
