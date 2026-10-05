extends "res://tests/quest_auto_background_ui_test.gd"
## Real remote snapshot reaches ClientState and the production chip stays
## closed. Synthetic state below tests only the display's strict gate.
func projection()->Dictionary:
	return {"running":false,"phase":"stopped","message":"合成预算记录","budget":{"enabled":false,"reason":"限时刷物尚未开放。","default_limit_minutes":30,"activity":"storage_paused","finish_current_battle":false,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":{"step_id":"jewels:hunt:2760","budget_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":0,"revision":1,"target_item_id":2760,"target_count":1,"limit_ms":1000,"saved_used_ms":500,"used_ms":1200,"limit_reached":true,"existing_items":2,"new_items":1,"saved_battles":3}}}
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	remote_mode=true
	backend_node=Backend.new();backend_node.set_process(false);root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Capability UI server starts on port zero"):return
	if not await create_world():return
	world.set_process(false)
	world.quest_helper_menu.close_menu()
	var chip=world.find_child("QuestAutoChip",true,false)
	if not check(world.backend==null and world.state.capabilities.get("quest_loot_enabled") is bool and not world.state.quest_loot_enabled(),"Remote production snapshot carries a disabled server-owned capability"):return
	if not await ready(func():return not chip.visible,"Empty disabled ledger adds no background chip"):return
	# Even if a stale/internal projection claims enabled and contains counters,
	# the actual remote capability remains the only UI gate.
	world.state.derived.quest_auto=projection()
	world.state.derived.quest_auto.running=true
	world.state.derived.quest_auto.budget.enabled=true
	if not await ready(func():return chip.visible and not chip.loot_panel.visible and chip.stop_button.visible and not chip.restore_button.text.contains("1200 ms"),"Nonempty enabled-looking budget cannot open the panel without strict capability"):return
	world.state.derived.quest_auto.budget.entry=null
	world.state.derived.quest_auto.budget.recovery_blocked=true
	if not await ready(func():return not chip.loot_panel.visible and chip.restore_button.text.contains("恢复锁定（只读警告）"),"Real recovery-lock shape remains a read-only warning while panel is closed"):return
	# Missing or malformed capability data on a later profile message revokes
	# the client-side display permission. This is the same ClientState consumer
	# used by production; server command authorization remains server-owned.
	var next_profile:Dictionary={"type":"profile","rev":world.state.rev+1,"profile":world.state.profile.duplicate(true),"derived":world.state.derived.duplicate(true),"options":world.state.options.duplicate(true)}
	next_profile.capabilities={"quest_loot_enabled":true};world.state.apply(next_profile)
	if not check(world.state.quest_loot_enabled(),"Strict true capability is active before the stale-field negative"):return
	next_profile.rev+=1;next_profile.erase("capabilities");world.state.apply(next_profile)
	if not check(world.state.capabilities.is_empty() and not world.state.quest_loot_enabled(),"Missing capability in profile update clears the old value and fails closed"):return
	next_profile.rev+=1;next_profile.capabilities="true";world.state.apply(next_profile)
	if not check(world.state.capabilities.is_empty() and not world.state.quest_loot_enabled(),"Malformed capability container fails closed"):return
	next_profile.rev+=1;next_profile.capabilities={"quest_loot_enabled":"true"};world.state.apply(next_profile)
	if not check(not world.state.quest_loot_enabled(),"Non-boolean capability cannot open the feature"):return
	var enabled_projection:=projection();enabled_projection.running=true;enabled_projection.budget.recovery_blocked=false
	var enabled_derived:Dictionary=world.state.derived.duplicate(true);enabled_derived.quest_auto=enabled_projection
	next_profile.rev+=1;next_profile.capabilities={"quest_loot_enabled":true};next_profile.derived=enabled_derived;world.state.apply(next_profile)
	if not await ready(func():return chip.loot_panel.visible and chip.loot_panel.content().contains("1200 ms / 上限 1000 ms"),"Only a strict true capability opens the synthetic display fixture"):return
	var panel=chip.loot_panel
	if not check(panel.controls.disabled and panel.controls.pressed.get_connections().is_empty(),"No loot command callback exists"):return
	if not check(panel.content().contains("尚未开放") and panel.content().contains("预算暂停计时") and panel.content().contains("初始已有 2（非当前库存）"),"Read-only display distinguishes unavailable capability, storage pause and initial holdings"):return
	if not check(chip.stop_button.visible,"Existing general stop remains available for a running task"):return
	world.state.derived.quest_auto.budget.entry.used_ms=1500
	if not await ready(func():return panel.content().contains("1500 ms"),"Same revision newer cached sample redraws"):return
	world.state.derived.quest_auto.budget.entry=null
	world.state.derived.quest_auto.budget.recovery_blocked=true
	if not await ready(func():return panel.content().contains("中断时段用时不确定") and not panel.content().contains("本步已用"),"Root lock with null entry removes old counters"):return
	world.state.derived.quest_auto.budget.recovery_blocked=false
	world.state.derived.quest_auto.running=false
	backend_node.publish()
	if not await ready(func():return not world.state.quest_loot_enabled() and not chip.visible,"Next real server profile publication revokes the synthetic display capability"):return
	world.state.derived.quest_auto={"running":true,"phase":"waiting_boss","quest_id":12,"message":"原守卫","can_continue":false,"budget":{}}
	if not await ready(func():return chip.visible and not panel.visible and chip.restore_button.text.contains("等待手动 Boss"),"Existing Boss chip remains with empty budget"):return
	world.music.stop();world.effect.stop();world.link.close();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Panel scene disposed"):return
	server_node.queue_free();backend_node.queue_free()
	print("LOOT PANEL SYNTHETIC SCENE: PASS")
	quit(0)
