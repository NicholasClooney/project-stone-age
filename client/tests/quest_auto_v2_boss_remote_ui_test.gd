extends "res://tests/quest_auto_background_ui_test.gd"
## Original fixed guard route/troop + manual WS battle commands + real UI continue.
## Runner wait hook and high player stats are explicit fixtures, not full quest proof.
func continue_command()->Dictionary:
	var auto:Dictionary=world.state.derived.quest_auto
	return {"type":"quest_auto_continue","quest_run_id":auto.run_id,"quest_step_id":auto.step_id,"quest_revision":auto.revision}
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	remote_mode=true
	backend_node=Backend.new();backend_node.set_process(false)
	for key in backend_node.session._profile.inventory:backend_node.session._profile.inventory[key]=0
	backend_node.session.gm_raise_level(-1,80)
	backend_node.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
	preload("res://server/progression.gd").refresh(backend_node.session._profile.player)
	backend_node.session._profile.player.hp=backend_node.session._profile.player.max_hp
	backend_node.session._profile.no_random_encounters=true
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-fixed-guards.json"))
	var guards:Array=[]
	for fixture in fixtures:guards.append_array(fixture.npcs)
	backend_node.quest_catalog.npcs.append_array(guards)
	backend_node.quest_catalog.enabled_events.append_array([9,10,11,12,20,21,22])
	var npc:Dictionary=guards[0]
	if not check(preload("res://tests/support/fixed_guard_route.gd").approach(backend_node,npc).ok,"Original protected guard route supplies real arrival"):return
	var talked:Dictionary=backend_node.handle({"type":"quest_talk","npc_id":npc.id})
	if not check(talked.ok,"Actual guard dialogue opens"):return
	if not check(backend_node.handle({"type":"quest_choose","token":talked.dialogue.token,"choice":"yes"}).ok and backend_node.battle_open,"Original guard starts real battle"):return
	backend_node.quest_auto.running=true;backend_node.quest_auto.strict_walk=true;backend_node.quest_auto.quest_id=11
	backend_node.quest_auto.identity.begin();backend_node.quest_auto.identity.select_step("ui:original-guard")
	backend_node.quest_auto.wait_boss(backend_node)
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Boss UI server port0"):return
	if not await create_world():return
	var pump:=LinkPump.new();root.add_child(pump)
	var other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port);pump.links=[other];other.connect_now()
	if not await ready(func():return other.online,"Second manual battle device connects"):return
	if not check(not backend_node.automation.running and not backend_node.quest_auto.owns_battle and world.backend==null,"Boss remains player-owned on remote backend-null UI"):return
	var early:=continue_command()
	if not check(not (await rpc(other,early)).ok,"Premature continue rejected over second socket"):return
	var expected:Array=npc.branches[0].guard.enemy_ids.map(func(id):return int(id))
	if not check(backend_node.session._pending.enemies.map(func(enemy):return int(enemy.source_enemy_id))==expected,"Unmodified original full guard troop"):return
	for index in range(100):
		var battle:Dictionary=backend_node.battle.snapshot()
		if not battle.active:break
		var target:=0
		for slot in range(battle.enemies.size()):
			if int(battle.enemies[slot].hp)>0:target=slot;break
		if not check((await rpc(other,{"type":"battle_command","action":"attack","target":target})).ok,"Manual attack command resolves original battle"):return
	if not check(not backend_node.battle.snapshot().active,"Original guard battle finishes"):return
	if not check((await rpc(other,{"type":"battle_close"})).ok,"Saved guard victory closes"):return
	backend_node.quest_auto.tick(backend_node,1.0)
	if not check(await Wait.settle(self,world),"Saved Boss waiting snapshot reaches UI"):return
	if not check(backend_node.quest_auto.snapshot(backend_node).can_continue and backend_node.quest_auto.phase=="waiting_boss","Saved win still waits for explicit continuation"):return
	if not check(not (await rpc(other,early)).ok,"Pre-victory revision cannot continue after victory"):return
	if not await ready(func():return not world.battle_view.visible,"Battle playback exits before opening task menu"):return
	world.quest_helper_menu.open_menu()
	if not await ready(func():return world.quest_helper_menu.find_child("QuestAutoContinue",true,false)!=null,"Boss handoff menu exposes continue"):return
	var resume=world.quest_helper_menu.find_child("QuestAutoContinue",true,false)
	if not check(not resume.disabled,"Saved victory enables actual UI control"):return
	var used:=continue_command()
	if not await click(resume):return
	if not check(await Wait.settle(self,world) and backend_node.quest_auto.phase=="travel","Explicit UI click resumes runner"):return
	if not check(not (await rpc(other,used)).ok,"Duplicate continue from other device rejected"):return
	if not check((await rpc(other,{"type":"quest_auto_stop"})).ok,"Stop test runner without advancing unrelated shell route"):return
	other.close();pump.queue_free()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Boss UI disposed"):return
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	print("QUEST AUTO V2 BOSS REMOTE UI: PASS")
	quit(0)
