# 第三阶段I结算验收矩阵

生产目录仍关闭；只定向，无full/live。以下区分纯候选、真实持久化、真实原路NPC和网络生命周期，不将候选等同完整任务通关。

| 要求 | 实际证据 | 边界 |
| --- | --- | --- |
| 四村×1–5继承/奖励/旗标/净容量 | transmigration_candidate_test，C锁源reward_pets/R原C规则，20候选普通Session校验、四村第一轮原子失败/读回 | 先前四链完成及祭品为显式fixture |
| 1–5转后继续加点/升级/存读 | transmigration_round_lifecycle_test，每轮原点池分配后普通_gain_xp升2级、再分配3点、完整读回；继承基底不变 | 测正常经验函数，未虚称每轮重新抓宠打满80级 |
| 普通宠与引用 | 同suite保普通UID、收藏、base/growth、VARIABLEAI；active与捕宠UID重排、骑乘解除；献宠active/ride/UID与旧index-only捕宠清空 | 7a9e1e08修旧index-only误指另一宠的真实问题 |
| 个人NPC与助手缓存 | transmigration_service_lifecycle_test，真实王成功保存后原四链/矿工所有实际NPC的cooldown/NpcWarp计数消失、TimeMan视觉保留、助手重新显示未开始 | 下一轮仍需等级/成人礼；三个实际公开门branch拒新Lv1角色，未用项目移动替代重做。没有额外重跑四条完整路线 |
| 真王原子交易 | transmigration_service_test，原portal、原五敌/十敌，两战分别savefail/真正写盘重试/close Warp、末门到王；两个真socket | 源目录与portal oracle隔离安装，生产world由C后续并集 |
| 重试/旧token/伪造 | 同suite：新预览使旧确认与迟到取消失效；错误UID/混入computed fields整拒；真实第二设备修改profile后旧确认拒；两次savefail同candidate/proof，成功后重放不发奖 | 同Backend每角色一个私有pending，不持久token |
| ACK丢失重连 | lifecycle suite确认客户端不设callback且不poll，服务器完成写盘后关闭该socket；新socket重连重试旧token被拒，完整候选值未重复改变 | 服务端真实提交，不以合成ACK冒充成功 |
| 旧历史保护 | migration suite逐v1–6未知正转真实读回保资产；count33不截断；unknown service suite由实际v6旧档load开始，真正两战/末门后王仅拒历史缺失 | 不捏造旧Q/L，不禁止普通路线游玩 |
| 2771–74离线消失 | logout suite实际存读与重复实例，source SHA/四原行验证；disconnect suite真实ProfileHub/两个认证socket逐一断开、最后设备离线、token重连，原Backend/四UID均保留；真正新load才清 | 沿既有角色load约定，不把单连接关闭当登出；仓库规则未改 |

## 日志

- `/private/tmp/stage-three-candidate-source-final.log`
- `/private/tmp/stage-three-round-lifecycle-final.log`
- `/private/tmp/stage-three-service-negative.log`
- `/private/tmp/stage-three-service-lifecycle.log`
- `/private/tmp/stage-three-disconnect.log`
- `/private/tmp/stage-three-unknown-service.log`
- `/private/tmp/stage-three-logout.log`
- 既有迁移/外围日志及完整依赖见`transmigration-integration-dependencies.md`。

## 尚待其他owner/主并集

C生产world/helper与精确导入命令、UI已报告真实WS/桌面390首轮通过的实际交付片，最后由主integrate/stage-three并集唯一full后再main。I未把这些外部任务宣称完成。监狱用户已裁B，fire独占original_prison_service和services.reply同token恢复；I不改choose，不另造网络命令。END53始终关闭。
