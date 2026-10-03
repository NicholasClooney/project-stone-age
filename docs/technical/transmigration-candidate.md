# 转生候选与持久化边界

`transmigration_candidate.gd::build` 是内部纯候选构造，不授到达权限、不读取客户端授权、不保存。服务须在调用前和一次保存前检查真实王身份、当前角色前态、私有到达凭证和选择UID。本片生产服务仍为关闭底座。

四村×五轮遵循R原C规则；原随身五槽由项目既有30槽扩容兼容，遍历全部随身且不动宠仓祭品。候选含同一事务的继承、旗标清留、扣宠、固定种子新宠、UID重排、新轮点池、返村位置。装备复核不迁移耐久；忠诚刷新只更新派生值，原VARIABLEAI保留。

`transmigration_candidate_test`注册为定向suite。四村20个候选均经普通Session完整校验；四村第一轮分别实测保存失败回滚、成功读回、同轮重放拒绝。另测30槽末位祭品、净容量、重复/错误UID、等级、出生缺失与未知历史保护。奖励测试数据来自真实encounter模板，尚未替代C待补的王reward_pets导出，也未伪装成合法NPC交易。

日志：`/private/tmp/stage-three-candidate-final.log`，0 failures。依赖I19a8/3bd0c75、R9142f27/443a70d/cd0857c、E5d866f3；当前并集还含A0f62cde与C1c0bd94/26e7fcb，生产启用另交。
