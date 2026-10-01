---
subject: "perf(client): keep the walking grid at one byte a cell"
title: "大地图寻路省 40–60 MB 内存"
---

- 地图上的寻路网格改成每格 1 字节，只在寻路时按起点终点附近临时建小网格：萨伊那斯从约 42 MB 降到 0.6 MB，加鲁卡从约 62 MB 降到约 1 MB。走的路线和以前一样短；跨整个岛的长距离第一次寻路会多花一点时间（电脑上约 0.15 秒）。
