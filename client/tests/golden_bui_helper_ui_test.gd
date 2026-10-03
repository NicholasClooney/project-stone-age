extends "res://tests/golden_bui_ui_test.gd"
func select_step(id:String) -> bool:
	return await click(world.quest_helper_menu.find_child("QuestStep_2_"+id.validate_node_name(),true,false))
func show_helper() -> bool:
	world.quest_helper_menu.open_menu()
	if not world.quest_helper_menu.detail_open:
		if not await click(world.quest_helper_menu.find_child("QuestHelper_2",true,false)):return false
	return await ready(func():return world.quest_helper_menu.selected_id==2 and world.quest_helper_menu.detail_open,"Actual remote task44 detail selected")
func model() -> Dictionary:
	for q in world.state.derived.get("quest_helper",{}).get("quests",[]):
		if int(q.event)==44:return q
	return {}
func run() -> void:
	root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
	if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
	host=Backend.new();root.add_child(host);host.quest_catalog.enabled_events=[44]
	host.session._profile.default_companions_claimed=true
	host.session._profile.no_random_encounters=true
	host.session.gm_raise_level(-1,30);host.session._profile.player.gold=100000
	var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Remote helper uses real server"):return
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://golden-bui-helper-ui.cfg";root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote helper scene ready"):return
	if not check(await Wait.settle(self,world) and world.backend==null,"Helper UI has no backend"):return
	world.helper_menu.open_menu()
	if not await click(world.helper_menu.find_child("HelperQuest",true,false)):return
	if not await click(world.quest_helper_menu.find_child("QuestHelper_2",true,false)):return
	if not check(model().title=="猜谜3兄弟" and model().steps.size()>=5,"Original job2 title and real step list published remotely"):return
	if not check(world.quest_helper_menu.find_child("QuestAutoStart_2",true,false)==null,"No unauthorized auto44 control"):return
	await proof("390x844-helper-entry-detail")
	if not await click(visit_button("golden44:buy:2755","arrival",2)):return
	if not await ready(func():return int(world.data.get("map_id",-1))==2020 and not world.area_transition_busy and not world.moving and not world.quest_helper_travel.active,"Helper stops at public ticket entrance"):return
	if not check(await Wait.settle(self,world) and not world.world_travel.quest_dialogue.active,"Public entrance does not impersonate a completed NPC interaction"):return
	if not await click_source("quiz/uketuke@2020:18:13"):return
	if not check(int(world.data.map_id)==2020 and world.cell.x<=16,"Helper reaches front of original counter, not behind wall"):return
	await proof("390x844-helper-original-ticket-counter")
	if not await choose("yes") or not await choose("ok"):return
	if not check(2755 in world.session.snapshot().original_items and int(world.session.snapshot().player.gold)==99400,"Actual clicks pay30x20 for original ticket"):return
	if not await show_helper():return
	if not await select_step("golden44:enter:811:2755"):return
	await proof("390x844-helper-ticket-reception")
	if not await click(visit_button("golden44:enter:811:2755","arrival",2)):return
	if not await ready(func():return int(world.data.get("map_id",-1))==811 and not world.area_transition_busy and not world.moving and not world.quest_helper_travel.active,"Helper stops before original ticket gate"):return
	if not check(await Wait.settle(self,world) and not world.world_travel.quest_dialogue.active,"Public gate requires actual source click"):return
	if not await click_source("genout/wpm_811_30_20@811:30:20"):return
	if not await choose("yes"):return
	if not await ready(func():return int(world.data.map_id)==800 and not world.area_transition_busy,"Original gate enters first floor"):return
	if not check(await Wait.settle(self,world) and not 2755 in world.session.snapshot().original_items,"Original gate consumes original ticket"):return
	var stale:=[{}]
	world.link.request({"type":"quest_visit","quest_id":2,"step_id":"golden44:enter:811:2755","mode":"near"},func(r):stale[0]=r)
	if not await ready(func():return not stale[0].is_empty(),"Stale remote helper request answered"):return
	if not check(not stale[0].ok and int(world.data.map_id)==800,"Old remote entrance target cannot replay after entry"):return
	if not await show_helper():return
	if not await select_step("golden44:coupon:800"):return
	await proof("390x844-helper-natural-coupon-step")
	world.quest_helper_menu.close_menu()
	# Reuse actual source services and each original portal; never place a
	# character directly in the protected reward room.
	if not await route_and_sync("quiz/equiz_01@810:29:16"):return
	if not await show_helper() or not await select_step("golden44:claim:810"):return
	await proof("390x844-helper-reward-explanation")
	if not await click(visit_button("golden44:claim:810","arrival",2)):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Original reward issuer approached"):return
	if not await choose("yes") or not await choose("ok"):return
	if not await show_helper() or not await select_step("golden44:exchange:810"):return
	await proof("390x844-helper-pet-exchange-explanation")
	if not await click(visit_button("golden44:exchange:810","arrival",2)):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and not world.world_travel.quest_dialogue.busy,"Original pet exchanger approached"):return
	if not await choose("yes") or not await choose("ok"):return
	if not check(model().status=="已完成" and world.session.snapshot().pets.size()==1,"Actual exchange updates remote helper END44 exactly once"):return
	if not await show_helper():return
	await proof("390x844-helper-completed")
	world.quest_helper_menu.close_menu();world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
	await process_frame
	print("GOLDEN BUI HELPER UI: %d failures"%failures)
	quit(1 if failures else 0)
