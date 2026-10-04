extends "res://tests/quest_auto_background_ui_test.gd"
## Real WS/game/runner/transactions. Initial public position, stats and pending
## axe delivery are fixtures; this tests UI integration, not six complete routes.
const Session=preload("res://server/game_session.gd")
func begin_job(job:int)->bool:
	world.quest_helper_menu.open_menu()
	world.quest_helper_menu.select_quest(job)
	var action=world.quest_helper_menu.find_child("QuestAutoStart_%d"%job,true,false)
	if not check(is_instance_valid(action) and not action.disabled,"New delivery button enabled %d"%job):return false
	if not await click(action):return false
	if not check(await Wait.settle(self,world),"New delivery start settles"):return false
	return check(backend_node.quest_auto.running and backend_node.quest_auto.quest_id==job and backend_node.quest_auto.strict_walk,"Real button starts correct strict job")
func pulse()->bool:
	backend_node.automation.tick(1.0)
	backend_node.quest_auto.tick(backend_node,0.21)
	if not check(await Wait.settle(self,world),"Authority pulse settles"):return false
	if backend_node.quest_auto.phase=="landing":
		if not await ready(func():return backend_node.quest_auto.phase!="landing","Real remote UI confirms map landing"):return false
	return true
func run()->void:
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(390,844)
	remote_mode=true
	backend_node=Backend.new();backend_node.set_process(false)
	# Start a real pending axe delivery at the public original village portal.
	Rules.set_flag(backend_node.session._profile,"now",3,true)
	Session.OriginalEquipment.add(backend_node.session._profile,2416)
	for command in [{"type":"gm_raise_level","index":-1,"target":80},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":500},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500},{"type":"gm_heal"}]:
		backend_node.handle(command)
	backend_node.session._profile.no_random_encounters=true
	var portal:Dictionary={}
	for link in backend_node.quest_helper.places.links(100).values():
		if int(link.to_map)==1300:portal=link;break
	if not check(not portal.is_empty(),"Original Mati village entrance exists"):return
	backend_node.automation.position_changed(100,Vector2i(int(portal.cell[0]),int(portal.cell[1])))
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Delivery UI server port0"):return
	if not await create_world():return
	if not await begin_job(12):return
	world.quest_helper_menu.close_menu()
	var chip=world.find_child("QuestAutoChip",true,false)
	if not await ready(func():return chip.visible and chip.restore_button.text.contains("连续原路"),"New job survives closing with correct floating mode"):return
	backend_node.quest_auto.tick(backend_node,0.21)
	if not check(backend_node.quest_auto.phase=="landing" and backend_node.automation.position_map==1300,"Original portal creates actual landing wait"):return
	if not await ready(func():return backend_node.quest_auto.phase=="travel" and int(world.data.map_id)==1300,"Remote backend-null UI loads and acknowledges original landing"):return
	if not check(await Wait.settle(self,world),"Landing settles"):return
	for index in range(300):
		if not backend_node.quest_auto.running:break
		if not await pulse():return
	if not check(Rules.flag(backend_node.session.snapshot(),"ended",3),"Remote pending axe is delivered through original transaction"):return
	if not await begin_job(13):return
	world.quest_helper_menu.close_menu()
	backend_node.encounter_rng.seed=7
	backend_node.session._profile.no_random_encounters=false
	var battle_seen:=false
	var continued:=false
	for index in range(700):
		if backend_node.quest_auto.phase=="battle":
			battle_seen=true
			backend_node.session._profile.no_random_encounters=true
			if not check(backend_node.quest_auto.owns_battle and backend_node.automation.compact_active,"Ordinary random battle uses authorized compact lifecycle"):return
		if battle_seen and backend_node.quest_auto.running and backend_node.quest_auto.phase!="battle":
			continued=true;break
		if not backend_node.quest_auto.running:break
		if not await pulse():return
	if not check(battle_seen and continued and str(backend_node.battle_state.get("outcome","")) in ["win","captured"],"Real ordinary encounter settles successfully and continues strict delivery"):return
	if not await ready(func():return not world.battle_view.visible and chip.visible,"After battle the running task chip returns"):return
	# Induce a genuine plan rejection from missing authority inventory. This is
	# a state fixture, not a claim that a player discarded during running.
	Rules.remove_items(backend_node.session._profile,"2423")
	if not await pulse():return
	if not await ready(func():return chip.visible and chip.restore_button.text.contains("已停止"),"Real manual snapshot changes chip from running to stopped"):return
	if not check(not backend_node.quest_auto.running and backend_node.quest_auto.phase=="manual" and chip.restore_button.text.contains(backend_node.quest_auto.pause_reason),"Remote chip preserves actual plan failure reason"):return
	var stopped:Dictionary=backend_node.session.snapshot()
	if not await pulse():return
	if not check(backend_node.session.snapshot()==stopped and not backend_node.quest_auto.running,"Manual state never resumes by itself"):return
	# Simulate completed manual recovery; starting still requires the UI button.
	Session.OriginalEquipment.add(backend_node.session._profile,2423);backend_node.publish()
	if not check(await Wait.settle(self,world),"Manual recovery state settles"):return
	if not await click(chip.restore_button):return
	if not check(world.quest_helper_menu.selected_id==13 and not backend_node.quest_auto.running,"Restore opens correct quest without resuming"):return
	if not await begin_job(13):return
	world.quest_helper_menu.close_menu()
	if not await click(chip.stop_button):return
	if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"Real UI stop cancels restarted strict intent"):return
	# Download completion from an explicitly cancelled start cannot restart it.
	var original_packs=world.asset_packs
	var gate:=PackGate.new();root.add_child(gate);world.asset_packs=gate
	world.quest_helper_travel.start_auto(13)
	if not check(gate.waiting.is_valid(),"Delayed download holds start"):return
	world.quest_helper_travel.cancel();gate.finish(true)
	if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"Late download after cancel cannot start task"):return
	world.asset_packs=original_packs;gate.queue_free()
	if not await begin_job(13):return
	world.quest_helper_menu.close_menu()
	world.link.close()
	if not await ready(func():return backend_node.quest_auto.detached,"Strict owner disconnect waits without cancelling"):return
	var detached_profile:Dictionary=backend_node.session.snapshot()
	var detached_position:Vector2i=backend_node.automation.position_cell
	backend_node.quest_auto.tick(backend_node,45.0)
	if not check(backend_node.quest_auto.running and backend_node.session.snapshot()==detached_profile and backend_node.automation.position_cell==detached_position,"Detached strict intent does not advance or time out"):return
	world.link.connect_now()
	if not await ready(func():return world.link.online and not backend_node.quest_auto.detached,"Remote strict intent reattaches through actual position report"):return
	if not check(await Wait.settle(self,world),"Strict reconnect settles"):return
	var pump:=LinkPump.new();root.add_child(pump)
	var other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port)
	pump.links=[other];other.connect_now()
	if not await ready(func():return other.online,"Second real device connects"):return
	if not check((await rpc(other,{"type":"quest_auto_stop"})).ok,"Second same-profile device stops strict task"):return
	if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"First device observes other-device stop"):return
	other.close();pump.queue_free()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Remote delivery UI disposed"):return
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	print("QUEST DELIVERY REMOTE UI: PASS")
	quit(0)
