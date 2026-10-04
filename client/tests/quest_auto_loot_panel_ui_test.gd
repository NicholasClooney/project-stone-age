extends "res://tests/quest_auto_background_ui_test.gd"
## Real scene/chip/panel loading, synthetic ClientState projection only.
## No core ledger / WebSocket budget / pixels / transport isolation evidence.
func projection()->Dictionary:
	return {"running":false,"phase":"stopped","message":"合成预算记录","budget":{"enabled":false,"reason":"限时刷物尚未开放。","default_limit_minutes":30,"activity":"storage_paused","finish_current_battle":false,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":{"step_id":"jewels:hunt:2760","budget_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":0,"revision":1,"target_item_id":2760,"target_count":1,"limit_ms":1000,"saved_used_ms":500,"used_ms":1200,"limit_reached":true,"existing_items":2,"new_items":1,"saved_battles":3}}}
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	if not await create_world():return
	world.set_process(false)
	world.quest_helper_menu.close_menu()
	var chip=world.find_child("QuestAutoChip",true,false)
	world.state.derived.quest_auto=projection()
	if not await ready(func():return chip.visible and chip.loot_panel.visible and chip.loot_panel.content().contains("1200 ms / 上限 1000 ms"),"Production chip loads panel for retained synthetic history"):return
	var panel=chip.loot_panel
	if not check(panel.controls.disabled and panel.controls.pressed.get_connections().is_empty(),"No loot command callback exists"):return
	if not check(panel.content().contains("尚未开放") and panel.content().contains("预算暂停计时") and panel.content().contains("初始已有 2（非当前库存）"),"Disabled history distinguishes storage pause and initial holdings"):return
	if not check(not chip.stop_button.visible,"Historical budget does not create a general stop action"):return
	world.state.derived.quest_auto.budget.entry.used_ms=1500
	if not await ready(func():return panel.content().contains("1500 ms"),"Same revision newer cached sample redraws"):return
	world.state.derived.quest_auto.budget.entry=null
	world.state.derived.quest_auto.budget.recovery_blocked=true
	if not await ready(func():return panel.content().contains("中断时段用时不确定") and not panel.content().contains("本步已用"),"Root lock with null entry removes old counters"):return
	world.state.derived.quest_auto.budget.recovery_blocked=false
	if not await ready(func():return not chip.visible,"Default disabled empty history adds no persistent bar"):return
	world.state.derived.quest_auto={"running":true,"phase":"waiting_boss","quest_id":12,"message":"原守卫","can_continue":false,"budget":{}}
	if not await ready(func():return chip.visible and not panel.visible and chip.restore_button.text.contains("等待手动 Boss"),"Existing Boss chip remains with empty budget"):return
	world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Panel scene disposed"):return
	print("LOOT PANEL SYNTHETIC SCENE: PASS")
	quit(0)
