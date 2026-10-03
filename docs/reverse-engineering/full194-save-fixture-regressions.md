# full194：启用态与魅力存读夹具修正

基线严格为`integrate/stage-three`的`7b358be3618e82b1b74406c8cedb8ff234dcd535`。独立分支`fix/stage-three-save-regressions`，沿pool-d；旧`feat/stage-three-settlement`保留。本片仅测试和文档，不修改Session、服务、descriptor或实际资产。

## 两个根因

1. `transmigration_migration_test`把第三阶段底座关闭时的三命令统一拒绝预期套在已获批准的生产启用状态上。现先核真实王投影可见；合法形状但无路线的preview精确拒绝距离/路线，伪confirm/cancel精确拒绝过期token且profile/pending不变。随后仅在该独立Backend目录中移除48–52标签，显式测试关闭descriptor语义，原三命令与客户端伪enable均仍拒绝。未回退生产启用。
2. `original_charm_test`先在边界测试后删除v7必填`player.transmigration`，又用零转Lv2人物直接写入原Lv10护符2427装备槽；完整存档验证会分别拒绝这两处状态。原用例独立复现读回失败。先恢复count0后新完整验证仍失败，从`OriginalEquipment.valid`与2427定义定位第二处；并非Charm或金币被交易改错。

保留缺转数的旧输入仅用于纯`Charm.cost`计算（Lv2仍400）；新增v7缺字段拒绝负例。保留Lv2护符夹具的费用400和装备无效断言，再用已有GM升级API到原Lv10装备门槛，真实交易原费2000、base Charm60→65、装备Charm-1不参与收费；增加金币精确扣2000断言。原金币/Charm真实保存读回断言保留，另核保存前完整v7和实际磁盘JSON完整有效。没有把非法状态导入逻辑改成宽容，也未把坏档转数历史伪补成0。

## 定向日志

- `/private/tmp/full194-charm-before.log`：指定基线独立复现原存读失败。
- `/private/tmp/full194-charm-final.log`：仅恢复count后仍失败，完整profile/磁盘验证暴露独立装备问题。
- `/private/tmp/full194-charm-final-2.log`：原魅力全部边界、失败回滚、token、装备modifier、完整保存读回PASS。
- `/private/tmp/full194-migration-final.log`：旧v1–6/未知历史/原子候选/自然点池及新增启用/关闭隔离矩阵0 failures。

仅低并发定向，未运行full、未导入symlink资产、未接触main/live/真实save。两suite已有注册，不新增或删套。
