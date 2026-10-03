# 野外抽战位置权威修复

## 问题与范围

原 `wild_encounter` 与 `field_step` 直接把请求中的 map/cell 传给 EncounterCatalog；`Automation.start` 又用同一参数调用 `_set_position`，导致尚未移动的客户端可以选择别处敌群。旧 `auto/name=set` 可改任意自动化内部字段，能再次伪造位置或冻结的 hunt/flow 来源。

本片只修抽战来源，不改敌群权重、RNG算法、掉落率、原背包条件、任务专用掉落限制、捕宠直达白名单或任务合法到达政策。普通 `report_position` 的移动/门规则仍由已有服务器模块决定；本片不是全地图移动规则重写。

## 生产接点

|入口|权威校验与来源|
|---|---|
|Backend `_handle`|wild/field_step 必须带完整有效整数坐标；auto_start/auto/auto_step/stationary若携带坐标只作一致性校验。拒绝先于停活动、撤对话。auto/set整请求拒绝，不能部分写合法字段。|
|`wild_encounter`|公共内部调用也核实际 `automation.position_map/cell`，用此位置取区域、抽敌群。未知位置拒绝。战斗仍开窗或pending待保存时不得新抽。|
|`_cmd_field_step`|先核坐标，再用服务器当前位置推进原pressure/RNG；不遇敌开关不绕校验。等待结算时不得推进压力或重抽。|
|`Automation.start/_start_battle_runner`|删除客户端参数移动；有坐标则只校验，真正移动仍走已有服务器位置接口。|
|自动练级 `step`|已有战斗按原冻结状态继续；下一次治疗/挑敌/借敌/开战前核origin与当前实际位置。|
|慢搜 `_scan_index/_open_hit`|计数、回放与入战前核服务器实际点；旧客户端显式hunt_scan也不能绕过。|
|native `_fast_process`|启动及接收候选前核位置；失配停止原helper，不采纳异地结果、计数或种子游标。native格式与算法不变。|
|队列 `_replay_candidate/_showcase_capture`|候选回放/抓宠入战前核冻结点；普通 `flow_step` 原有位置保护保留。|
|原地遇敌|原模块一直使用服务器当前位置并检查冻结点；其真实tick调用同一受保护field_step。|
|组队|Hub原成员移动/独立遇敌拒绝保留。队长真实report先在Hub完成跟随、再用队长实际点抽战；成员无需伪装在队长的新格。|
|恢复|原服务器resume文件恢复位置，try_resume先核当前位置；不是客户端auto_start授予移动。|

生产 `GameAreas.handle_arrival` 先 `report_position()`，再 `field_step`。同一WebSocket请求顺序已保证前者先处理，不需要客户端新增绕行或延迟特例。被另一设备超越的旧坐标请求拒绝并在服务器打印 `[遇敌位置拒绝]`，包含请求点与实际点。

`roll_at`/EncounterCatalog仍可作为纯源算法回放器使用；纯算法调用不能创建pending或开战。生产入战链都经上表的位置检查。已有审核的“借用高等级敌群”是显式项目功能：服务器选审核池、独立持久RNG、预测时核origin未变、不移动角色，本片保留。管理员开发战斗配置接口不属野外区域抽样，不增加其权限。

## 旧 auto/set 字段完整盘点

|原UI包装属性|发送的内部字段|生产写调用|
|---|---|---|
|training_helper.starting_ride|starting_ride|没有；旧测试准备|
|pet_workflow.phase/reason/pet_id|flow_phase/flow_reason/flow_pet_id|没有；旧测试准备|
|stored_count/last_result/last_stored_id/last_stored_total|flow_stored_count/flow_last_result/flow_last_stored_id/flow_last_stored_total|没有|
|kept_count/collected_count/pruned_count/released_count|flow_kept_count/flow_collected_count/flow_pruned_count/flow_released_count|没有|
|predicted_rejects/best_predicted|flow_predicted_rejects/flow_best_predicted|没有|

不是按`_seam`名字推断：逐一核全部setter、文件内部赋值、client/scripts内属性写调用，只有测试在写上述属性。删除两个UI `_seam` 和这些内部setter，保留只读展示。四测试（pet_stat_workflow、keep_rule、pet_workflow_reload、training_helper）改用 `tests/support/automation_fixture.gd` 在测试端准备本地Backend并发布状态；不存在网络命令、客户端local开关或生产UI写backend路径。

真正公开设置继续走已有 `set_automation_settings` 类型/范围白名单；启动仍auto_start、停止仍原命令。没有把用户可编辑的训练/捕宠设置移除。未知字段混合法设置也保持整包拒绝。

## 验收与夹具边界

新增并注册 `wild_position_authority_test`：真实Backend/Session、双socket、真实Hub普通跟随→队伍遇敌，跨图/同图/畸形坐标、伪来源、内部set与混合字段拒绝；无RNG/pressure/profile/pending改动；慢搜/native移动后停止。矿石以隔离测试角色持原许可、初始服务器位置31801(37,48)为前提，核原碰撞可走且仍为area356，用真实原表seed27抽到1043，保持原负值，失败保存与重复失败保留同一claims，成功重试一矿并幂等。

新增并注册 `wild_authority_ui_test`：本机与实际WebSocket GameScene，真鼠标hover/点击训练、抓宠开始/停止，设置保存及重开恢复，remote无本地Backend。headless验证交互与权威，不宣称像素截图。

旧纯Backend测试过去以auto_start同时设置初始位置，现先明确report_position；旧四测试内部阶段fixture迁到tests/support。原业务断言、种子和真实捕宠/训练/队列流程保留。矿工与木材任务旧fixture由六链owner适配（其独立片a974e50，前置a0f9c82→ce72d53→7db9811；矿工从5F真楼梯走到1F的37,48），不在本片争写；四宝珠原套件已先走helper至服务器实际点，无需改。

定向执行日志与最终通过统计见本批外部交接记录；未运行full，不改main/live/真实save。无需重导原资产；合并后重新构建正常客户端/服务器代码即可。

### 本轮定向日志

- `/private/tmp/wild-authority-regression-final.log`：14/14；含新UI、本机字段迁移、原抓宠目标/摸底/清场/挑敌群/真实审核借敌群与native线程设置。各suite细日志：`/private/var/folders/lc/kqklvgsj5fvckh6dfrrd3zdr0000gn/T/stone-age-suites-x_6jfy80`。
- `/private/tmp/wild-authority-second-targeted.log`：4/4；原fast_hunt_flow的真实native/慢速同seed交接、LAN自动练级真实战斗及组队恢复，与新权威/字段迁移回归。
- `/private/tmp/wild-authority-initial-targeted.log`：Backend自动练级、stationary、training UI、reload和keep_rule已绿；当时pet_stat_workflow失败是新fixture漏发布状态，已由tests/support适配并在最终14/14通过。此初始日志不作为整批通过证据。
- `/private/tmp/wild-authority-location-final.log`：11/12；真实GameAreas行走、原地遇敌远程UI、梦幻审核捕宠真点击、角色Hub/队伍精灵、稀有点与新权威suite均过。唯一hunt_resume旧fixture缺显式位置，修正后 `/private/tmp/wild-authority-resume-final.log` **2/2**（hunt_resume + 新权威），目录 `stone-age-suites-tf0yc155`。原异地恢复拒绝断言保留，新增确实启动成功断言。
- `/private/tmp/wild-position-walkable-final.log`：新权威套件最终以37,48可走点核碰撞/原区域，保seed27；并补真实Hub三人完整战斗结算、各自关闭，不留下待保存战斗。

第一次直接沙箱启动Godot在RotatedFileLogger初始化因测试用户目录写权限崩溃，未进入套件；改为授权的后台测试环境，仍使用隔离测试user目录。另新UI/远程夹具首轮漏传ws_link.poll(delta)、错误读取local_link.online已修；最终日志须无SCRIPT ERROR。没有以重跑掩盖未知波动。
