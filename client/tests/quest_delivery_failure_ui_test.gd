extends "res://tests/quest_delivery_remote_ui_test.gd"
## Actual ordinary encounters and battle resolution over WS. Only initial
## stats/public position/pending delivery and failing save path are fixtures.
func run()->void:
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(390,844)
	remote_mode=true
	for save_failure in [false,true]:
		if not await failure_case(save_failure):return
	print("QUEST DELIVERY FAILURE UI: PASS")
	quit(0)
func failure_case(save_failure:bool)->bool:
	backend_node=Backend.new();backend_node.set_process(false)
	Rules.set_flag(backend_node.session._profile,"now",3,true)
	Session.OriginalEquipment.add(backend_node.session._profile,2416)
	if save_failure:
		for command in [{"type":"gm_raise_level","index":-1,"target":80},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":500},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500},{"type":"gm_heal"}]:
			backend_node.handle(command)
	else:
		for stat in ["vitality","strength","toughness","dexterity"]:
			backend_node.handle({"type":"gm_set_base_stat","index":-1,"stat":stat,"value":0})
		backend_node.session._profile.active_pet=-1
		backend_node.session._profile.player.hp=backend_node.session._profile.player.max_hp
		for key in backend_node.session._profile.inventory:backend_node.session._profile.inventory[key]=0
	backend_node.automation.position_changed(100,Vector2i(637,493))
	backend_node.encounter_rng.seed=7
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Failure UI server port0"):return false
	if not await create_world():return false
	if not await begin_job(12):return false
	world.quest_helper_menu.close_menu()
	var chip=world.find_child("QuestAutoChip",true,false)
	for index in range(100):
		if backend_node.quest_auto.phase=="battle" or not backend_node.quest_auto.running:break
		if not await pulse():return false
	if not check(backend_node.quest_auto.phase=="battle" and backend_node.quest_auto.owns_battle,"Actual random encounter starts before failure"):return false
	if save_failure:
		remove_tree("user://delivery-ui-missing-save")
		backend_node.save_path="user://delivery-ui-missing-save/save.json"
	for index in range(100):
		if not backend_node.quest_auto.running:break
		if not await pulse():return false
	var reason:String=backend_node.quest_auto.pause_reason
	print("FAILURE EVIDENCE: save=%s outcome=%s phase=%s reason=%s"%[save_failure,backend_node.battle_state.get("outcome",""),backend_node.quest_auto.phase,reason])
	if not check(not backend_node.quest_auto.running and backend_node.quest_auto.phase=="manual" and not reason.is_empty(),"Actual failure publishes terminal manual reason"):return false
	if save_failure:
		if not check(reason.contains("保存失败") and str(backend_node.battle_state.get("outcome",""))=="win","Actual won battle fails actual disk save"):return false
	else:
		if not check(str(backend_node.battle_state.get("outcome",""))=="defeat" and reason.contains("未获胜"),"Actual weak character defeat reaches manual"):return false
	if not await ready(func():return chip.visible and chip.restore_button.text.contains("已停止") and chip.restore_button.text.contains(reason),"Failure chip retains exact authority reason"):return false
	if not check(not chip.stop_button.visible and not chip.restore_button.text.contains("连续原路自动推进"),"Failure chip does not imply running"):return false
	backend_node.save_path=""
	var before:Dictionary=backend_node.session.snapshot()
	var position:Vector2i=backend_node.automation.position_cell
	backend_node.quest_auto.tick(backend_node,45.0)
	if not check(await Wait.settle(self,world),"Stopped failure state settles"):return false
	if not check(not backend_node.quest_auto.running and not backend_node.automation.running and backend_node.session.snapshot()==before and backend_node.automation.position_cell==position,"Repairing save or waiting never auto-restarts failed task"):return false
	if not check(chip.visible and chip.restore_button.text.contains(reason),"Failure reason survives later snapshots"):return false
	# Save failure can leave the completed battle open for player confirmation;
	# this test never closes it or resumes on the player's behalf.
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Failure remote UI disposed"):return false
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	return true
