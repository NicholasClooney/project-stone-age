# 第三阶段启用后的目录投影 oracle

基线 `integrate/stage-three` 的 `7b358be3618e82b1b74406c8cedb8ff234dcd535`。full194 的 `quest_catalog_lookup_test`、`quest_catalog_source_test` 失败来自测试独立全数组 oracle 未覆盖新增的空 branches 服务类型，不是本次发现的产品投影差异。

旧 reference 处理 TimeMan、GoldenBui、购壶，其余一律按启用 changeevent 分支过滤。因此 `original_transmigration` 精灵王及五个 `original_prison` 在旧 expected 中被丢弃；生产已有精确身份核验，会返回其完整只读投影。模块公开启用 48–52 后，这个遗漏可见。

修正仅在上述两个测试文件中：

- 用独立的 `tests/fixtures/transmigration-final-source.json` 审核记录和显式六 ID 集合构建特殊类型预期，不调用生产 `_project_active_npc` 或 `prison_catalog_identity.valid` 产生 expected。
- 核 source/create/ordinal/events/name/map/cell/graphic/facing/branches/kind/handler/service_id；Prison 核原 `prison` 和 `source_fields`、拒绝旧虚构 prison_role；王核 schema/rules。个人 override 不能使这些固定服务变成合法投影。
- 生产集合必须恰有王和五 Prison，完整源 fixture 字段逐项相等。导入附加 path/bitmap/offset 等字段不删，仍经原全数组、单 ID、source 投影精确等值和深修改隔离测试。
- 明确复制启用事件，再从隔离 catalog 去除 48–52 验 disabled；不能把生产启用数组误称为 closed。随后恢复原启用数组，继续全部旧个人移动/隐藏、区域出生、共享 event12、重复 ID、同源多图、12 helper entry 和代表 snapshot 断言。

产品文件/descriptor/导入器/素材未改。使用主已有只读资产，实际 catalog SHA256 `c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92`，314 NPC、339 items。未运行 importer 或 editor import。

两套串行定向通过：lookup 4.501 秒，source 11.177 秒（Python monotonic 实际总耗时）；退出 0，日志无 SCRIPT ERROR、ERROR:、FAIL:，结尾均 0 failures。完整日志保存在 `/private/tmp/tmux-agents/spirit-water/stage-three-projection/`。未重跑 full，未操作 main/live。
