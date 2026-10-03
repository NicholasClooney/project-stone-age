# 原表可堆叠物品的受审单件创建

范围：梦幻重复奖、地精灵材料、火精灵材料、水精灵掉落所需的 33 个精确物品 ID。完整名单、原行号、原列与六份来源 SHA 见 `tools/quest_single_item_reviews.json`。参考版本为 `0c58fb6683a49a178a8ad845a8c296c2cb83bd81` 的源码，不能据此推断历史运行 binary 或其他版本。

## C 创建路径

- `gmsv/include/version.h:104,234` 启用 `_ITEM_MAXUSERNUM`、`_ITEMSET4_TXT`。
- `gmsv/item/item.c:40–53` 默认 `upin=1`、`canpile=0`；另一编译分支 151–152 相同。327–328 的配置字段对应 itemset 零基 24、25 列。
- `ITEM_getDefaultItemSetting:892–912` 复制默认值；读取每行在 1114 先初始化，1116–1118 初始化随机范围为零，1144–1147 只在 token 非空时覆盖整数。33 行均为 `['','1']`，所以创建数量保留 1，可堆叠标记为 1。
- `ITEM_makeItem:1358–1371` 复制原表实例并使用原字段随机范围；本字段范围为零。`ITEM_makeItemAndRegist:1375–1381` 注册一个实例。
- `gmsv/npc/npc_exchangeman.c:2487–2540` 的 `NPC_RandItemGet` 单次选择并创建一个实例，调用一次 `CHAR_addItemSpecificItemIndex`；满包则销毁待添加实例。2887–2898 按原奖励槽数抽选一次，没有合并重复条目。
- `gmsv/char/char_item.c:1017–1031` 的入包路径找一个空格并填入一个实例索引，不自动并堆。

这只证明本审核集合沿这些创建路径获得一个实例，不是通用堆叠实现。导入保留原始行、`source_pile` 和数量；运行仍每件一个 UID、一个格，物品说明明确堆叠未实现。没有扩大装备、使用效果或保存结构。

## 调用方 manifest 契约

1. 将注册表 `sources` 六项原样并入 manifest `sources`。
2. 从注册表 `items` 按本链真实导入 ID 选择记录，将这些记录的列表放入 `single_item_pile_reviews`。记录字段为 `id`、`source_line`、`columns`、`creation_quantity`、`audit`，必须完全一致。
3. 同时在 manifest `items` 列出这些真实使用物品。不能声明未导入项。

例：`single_item_pile_reviews: [{"id":1238,"source_line":1233,"columns":["","1"],"creation_quantity":1,"audit":"original-single-item-v1"}]`，再锁六份源并将 1238 列入 `items`。

未声明的显式 pile 字段、未知 ID、不同数量/列/行、缺失或变化的源 SHA、重复或未使用声明一律拒绝。后续新 ID 必须重新源审并修改中央注册表，不能仅靠 manifest 自行授权。四链不得另改 catalog 放宽。

## 定向验证

`python -m unittest discover -s tools -p test_quest_single_items.py`：33 项真实 catalog 导入、完整源 SHA、精确原列、未知/重复/未使用/非 1/缺锁拒绝。

`reviewed_single_items_test`：真实 Backend 的原任务事务，重复材料独立 UID/容量、最后一格、满包无并堆、save 失败 UID 回滚与重试、存档读回。此测试以事务边界为范围，不声称验证各精灵任务路线。各链需另做自己的真实交付/掉落与 UI 验收。
