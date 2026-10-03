# 梦幻原可重复随机谢礼

2026-10-03 用户选择 A：`seimu/event/event01_1` 与 `event01_2` 原零基 branch4 开放。≥35 级的原 OR 分支允许免费领先见之光，再从原 20 项抽一件；不强补 END4 条件。前三轮优先顺序不变，仍只有第三次原交付写 END34。重复分支 event=-1，不写完成位，未增加次数上限。NPC 对话与助手注明「原版行为：可重复」。

20 个原奖励 ID、顺序、条件均在 `test_dream_cave_source_audit.py` 核对。10 项原表 canpile 经共享 `38285f0` 单件审核；另外 8 武器、2 食物完整导入。奖励照发，尚未支持的魔法/效果仍显示 metadata，不因此授予装备或使用能力。先见之光原离线消失仍未实现。

## 验证边界

- 来源 4 测试：SHA、完整 20 项与原 OR 条件、前三轮写位、十敌七槽。
- `dream_repeat_reward_test`：真实 Backend 原对话 token、34/35 级边界、免费光、随机一件、连续重复、保存失败/重试、旧 token、旗标不变。后续捕宠/资格整合片已把每次领奖准备改为真实原入口、逐格迷宫、终战与成功保存Warp；不直接放领奖区授资格。
- `dream_repeat_ui_test`：390×844 静音离屏的生产远程 GameScene，鼠标真实点击领取/交付/道具详情；领奖房间为明确的测试 fixture。三张图片 `/private/tmp/dream-repeat-shots/` 均实际查看，日志 `/private/tmp/dream-repeat-ui.log`。事务日志 `/private/tmp/dream-repeat-reward.log`。
- 捕宠新白名单及通用合法到达资格由后续独立功能提交；本片不宣称解决所有任务捷径。后续整合见reviewed-capture-arrival-handoff.md；UI/事务fixture现通过正常终战取得记录，不给测试特权。

## 准确导入

在资产为可写 clone 的 pool 或主协调者的停服导入窗口执行：

```sh
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
.tools/asset-venv/bin/python tools/palette_images.py
.tools/asset-venv/bin/python tools/split_manifests.py
.tools/asset-venv/bin/python tools/plan_web_packs.py
./scripts/run.sh --headless --editor --import --quit
```

本片不改变 world，没有新增 world 导入或 battle art 需求；物品静态图随 quest importer 导入。本槽当前 registry 导入实际 242 NPC / 158 物品；其他代理后续模块加入会增加总数，不能用此总数覆盖其注册。
