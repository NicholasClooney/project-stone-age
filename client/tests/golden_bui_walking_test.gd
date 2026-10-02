extends "res://tests/brothers_golden_ui_test.gd"
## Exercise the production GameAreas.handle_arrival -> field_step -> battle path.
func run() -> void:
	root.unfocusable=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
	if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
	var host=Backend.new();root.add_child(host)
	host.session._profile.default_companions_claimed=true
	host.session.gm_raise_level(-1,70)
	for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,10000)
	host.session._profile.player.hp=host.session._profile.player.max_hp
	var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Production walk isolated server"):return
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://golden-bui-walk.cfg"
	root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and world.link.online,"Walking scene online"):return
	if not check(await Wait.settle(self,world) and world.backend==null,"Production walk uses remote authority"):return
	for map_id in [800,820,840]:
		if not check(world.world_catalog.field(map_id) and not bool(world.world_catalog.info(map_id).get("dev_only",false)),"Official challenge map participates in natural field steps"):return
		host.automation.position_changed(map_id,Vector2i(29,20),true)
		host.session.set_location(map_id,29,20)
		host.publish();host._emit({"type":"position","map_id":map_id,"cell":[29,20],"client":"golden-bui-walking-fixture"})
		if not await ready(func():return int(world.data.map_id)==map_id and world.cell==Vector2i(29,20) and not world.moving,"Original floor loaded via server position"):return
		if not check(await Wait.settle(self,world),"Walking map report settled"):return
		var before:=int(world.field_steps)
		for step in range(160):
			var target:=Vector2i(29,21) if step%2==0 else Vector2i(29,20)
			if not check(world.is_walkable(target),"Original collision allows test walking cell"):return
			world.walk_to(target)
			if not await ready(func():return world.cell==target and not world.moving or host.battle_open,"Production navigation reaches source collision cell"):return
			if not check(await Wait.settle(self,world),"Each production walk request settled"):return
			if host.battle_open:break
		if not check(host.battle_open and int(world.field_steps)>before,"GameAreas actual walking opens source random battle %d"%map_id):return
		if not await ready(func():return world.battle_view.visible,"Actual remote battle scene rendered"):return
		if not await ready(func():return world.battle_view.transition_tiles.is_empty() and not world.battle_view.is_animating() and world.battle_view.actors[1].sprite.is_visible_in_tree(),"Original battle transition and enemy entrance finished before pixel evidence"):return
		for enemy in host.session._pending.enemies:
			if not check(int(enemy.source_enemy_id) in range(1287+(map_id-800)/20*6,1293+(map_id-800)/20*6),"Natural troop belongs to original route group"):return
		await proof("390x844-walking-battle-%d"%map_id)
		for turn in range(30):
			var state:Dictionary=host.battle.snapshot()
			if not state.active:break
			var target:=0
			for index in range(state.enemies.size()):
				if int(state.enemies[index].hp)>0:target=index;break
			host.handle({"type":"battle_command","action":"attack","target":target})
		if not check(host.handle({"type":"battle_close"}).ok,"Naturally entered source battle settles"):return
		if not await ready(func():return not world.battle_view.visible,"Remote battle close releases walking input"):return
		if not check(await Wait.settle(self,world),"Natural battle close settled before next map"):return
	world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
	await process_frame
	print("GOLDEN BUI WALKING: %d failures"%failures)
	quit(1 if failures else 0)
