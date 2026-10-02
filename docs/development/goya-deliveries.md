# 哥亚贝壳与小猪爱情故事

`goya-deliveries`仅开放原END6、7、8，和END2南北岛送花、吉鲁新小猪23–26、END44/47问答链分开。`tools/goya_deliveries_quest_sources.json`锁定GB18030原脚本、实际create实例、原物品/宠物数据的SHA；七只提供辨认线索的乌力也保留原绑定与对白。

**贝壳**：哥亚一楼20401(12,13)年青人LV>0接NOW6；卡鲁它那4000(71,97)的玛丽娜丝商人在无贝壳时免费给两颗2414、已有一颗时补一颗、有两颗时不再给。年青人先检查至少两颗，收一颗给1级特洛昆（enemy44/template63）；否则只有一颗时收一颗给1级呼拔拔（enemy47/template72）。均写END6，不能重复拿宠。完成后贝壳丢失，商人可补一颗，不重发宠物。

**小猪**：持2414向一楼乌力斯凯接7领2425信，四楼乌力花店免费给2424月光花，到山顶乌力美交花信写END7。再次对话领2426回信，回一楼乌力斯凯处交回信，得1206红玉手环并写END8，贝壳保留。END7/8要求携贝壳，但不要求END6；已有其它来源贝壳也可接取。鲜花虽对白写半买半送，原脚本没有收费。

红玉手环原说明写攻2、防2、敏-2、魅1；原数值字段实际为攻3、防3、敏-3、魅2，按字段生效，并在物品说明及助手公开差异。原装备等级0、耐久2500000，无魔法与六抗性字段，未扩魔法系统。

**可达性与便利**：岛200(98/99,425)入口和20401–20406间原传送全为普通warp，无额外等级门槛。沿用已有哥亚六层地图。任务助手有接取、领贝壳、两种交宠结果、补领、领信、花店、交付及回信步骤，瞬移属于项目便利；自动执行未开放。信丢失可与原发放者取消并重接，按原规则扣1魅力。

**验证**：`tools/test_goya_deliveries_quest.py`精确核对12实例、只启用6/7/8、两宠模板、花店无收费和手环数值。`goya_deliveries_quest_test`用真实Session执行0/1/2/3贝壳、补领、独立于END6的小猪接取、满包/满宠、原奖励、每个交换保存失败回滚、重复提交、丢失恢复及完整save读回；两设备WebSocket竞争只能授予一次宠物。存档比较逐字段核对，允许JSON将StringName键转为String、整数形式元素值转为int，不放宽奖励内容。`goya_bracelet_equipment_test`核对装备和重复UID持久化。

`goya_deliveries_ui_test`在390×844真实离屏窗口通过实际助手/原对白/宠物/物品点击走完6–8；禁用测试启动赠宠，奖励头像确认为特洛昆。九张PNG逐张查看并留在临时目录，不提交。完整suite由父会话统一运行。

## 导入与复验

导入链为 `client/data/quest-modules.json` → `tools/quest_import_common.py:extend_registered_modules` / `load_quest_module` → `tools/goya_deliveries_quest_sources.json` 的 SHA 与脚本分支白名单 → `tools/import_early_quests.py` 输出原任务目录及 NPC 贴图。只合并注册的6/7/8；源码其他分支先筛选再解析。运行时由原任务目录读取，助手仅补步骤，没有私有奖励解释器。

在有独立 legacy 副本的工作池中运行：

```sh
.tools/asset-venv/bin/python tools/test_goya_deliveries_quest.py
.tools/asset-venv/bin/python tools/import_early_quests.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --reference references/chenmingbiao-stone-age
STONE_AGE_TEST_JOBS=2 ./scripts/test-all.sh --only goya_bracelet_equipment_test,goya_deliveries_quest_test,goya_deliveries_ui_test
```

像素证据另用用户授权的静音屏幕外渲染运行同一 UI suite，不能以 headless 的控件测试代替。截图包括两种奖励面板、真实点击流程，以及滚动至原属性差异说明；图像和日志不提交仓库。
