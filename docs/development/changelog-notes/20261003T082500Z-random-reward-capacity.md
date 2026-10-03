---
subject: "fix(quests): align random reward helper capacity with transactions"
title: "任务助手按交换后的实际空格判断随机奖励"
---
- 项目任务助手的随机奖励步骤按原物品删除后的净背包容量判断；满包持兑换材料时不再误报无法领取。
- 穿戴物不被当作空出的背包格，多件裸编号删除、指定数量及仅背包删除均复用服务端交易规则；无消耗的随机补领奖仍须有空格。
