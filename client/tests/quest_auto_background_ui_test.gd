extends "res://tests/original_quest_auto_test.gd"
var proof_dir:=OS.get_environment("STONE_AGE_PROOF_DIR")
var backend_node
var server_node
var remote_mode:=false
func run() -> void:
	root.gui_embed_subwindows=true
	root.content_scale_size=Vector2i.ZERO
	if not proof_dir.is_empty():
		if not check(DisplayServer.get_name()!="headless","Proof requires real renderer"):return
		DirAccess.make_dir_recursive_absolute(proof_dir)
	for remote in [false,true]:
		for dimensions in [Vector2i(1280,720),Vector2i(390,844)]:
			if not await exercise(remote,dimensions):return
	print("QUEST AUTO BACKGROUND UI: PASS")
	quit(0)
func shot(id:String) -> void:
	if proof_dir.is_empty() or not remote_mode:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(proof_dir.path_join(id+".png"))
func create_world() -> bool:
	var script=load("res://scripts/game.gd")
	if remote_mode:script.server_url_override="ws://127.0.0.1:%d"%server_node.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://quest-background.cfg"
	root.add_child(world)
	if not await ready(func():return not world.data.is_empty() and (not remote_mode or world.link.online),"Real world ready"):return false
	if not check(await Wait.settle(self,world),"Initial world settles"):return false
	if not remote_mode:backend_node=world.backend
	backend_node.set_process(false)
	return check(not remote_mode or world.backend==null,"Remote UI has no backend")
func begin() -> bool:
	world.show_adventure_menu("inventory")
	world.quest_helper_menu.open_menu()
	world.quest_helper_menu.select_quest(11)
	if not await click(world.quest_helper_menu.find_child("QuestAutoStart_11",true,false)):return false
	world.close_adventure_menu()
	return await ready(func():return backend_node.quest_auto.running and world.state.derived.get("quest_auto",{}).get("running",false) and world.quest_helper_menu.last_model==world.quest_helper_menu.refresh_key(),"Real button starts server intent and menu refreshes")
func escape() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
	root.push_input(event,true)
func exercise(remote:bool,dimensions:Vector2i) -> bool:
	remote_mode=remote
	root.size=dimensions
	if remote:
		backend_node=Backend.new();backend_node.set_process(false);root.add_child(backend_node)
		server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
		if not check(server_node.start()==OK,"Background UI server port0"):return false
	if not await create_world():return false
	# A single strict tick crosses an actual original portal, not a convenience
	# teleport to the NPC. Placement is a map-readiness fixture, not route proof.
	var portal:Dictionary={}
	for candidate in backend_node.quest_helper.places.links(1300).values():
		if int(candidate.to_map)==100:portal=candidate;break
	if not check(not portal.is_empty(),"Background fixture uses original village exit"):return false
	backend_node.session._profile.no_random_encounters=true
	backend_node.automation.position_changed(1300,Vector2i(portal.cell[0],portal.cell[1]))
	backend_node.publish()
	backend_node.emit_event({"type":"position","map_id":1300,"cell":portal.cell.duplicate(),"client":"fixture"})
	if not await ready(func():return int(world.data.map_id)==1300 and world.cell==Vector2i(portal.cell[0],portal.cell[1]) and not world.moving and not world.area_transition_busy,"Original portal fixture reaches real UI"):return false
	if not check(await Wait.settle(self,world),"Fixture placement settles before real start button"):return false
	if not await begin():return false
	var menu=world.quest_helper_menu
	var chip=world.find_child("QuestAutoChip",true,false)
	var prefix:="%dx%d"%[dimensions.x,dimensions.y]
	if not await click(menu.find_child("QuestHelperClose",true,false)):return false
	if not await ready(func():return chip.visible and not menu.visible,"Close leaves background chip"):return false
	backend_node.quest_auto.tick(backend_node,0.21)
	if not check(backend_node.quest_auto.phase=="landing" and backend_node.automation.position_map==100,"Strict tick crosses actual original portal and waits for UI"):return false
	if not await ready(func():return backend_node.quest_auto.phase=="travel" and int(world.data.map_id)==100 and world.cell==Vector2i(portal.target[0],portal.target[1]) and not world.area_transition_busy and not world.moving,"Closed helper still loads and confirms original portal step"):return false
	if not check(await Wait.settle(self,world),"Background step settles"):return false
	if not check(backend_node.quest_auto.running and root.get_visible_rect().encloses(chip.get_global_rect()),"Running chip fits viewport"):return false
	if not await ready(func():return not chip.restore_button.text.ends_with("当前步骤\n"),"Chip has current step"):return false
	await shot(prefix+"-closed-progress")
	if not await click(chip.restore_button):return false
	if not await ready(func():return menu.visible and not chip.visible,"Chip body restores helper"):return false
	if not check(backend_node.quest_auto.running,"Opening helper does not stop same task"):return false
	await shot(prefix+"-restored")
	escape()
	if not await ready(func():return chip.visible and not menu.visible,"Esc hides helper without stopping"):return false
	if not check(backend_node.quest_auto.running,"Esc preserved server intent"):return false
	await shot(prefix+"-esc")
	if not await click(chip.restore_button):return false
	if not await click(menu.find_child("QuestHelperMinimize",true,false)):return false
	if not await ready(func():return chip.visible and not menu.visible,"Explicit minimize leaves chip"):return false
	# A real existing automation chip must never overlap the new task bar.
	var other=preload("res://scripts/automation_chip.gd").new()
	chip.get_parent().add_child(other);other.setup(world,"布局验证",0,func():pass);other.show()
	if not await ready(func():return not chip.get_global_rect().intersects(other.get_global_rect()),"Background bar avoids automation slot"):return false
	var weak_other=weakref(other)
	other.queue_free()
	if not await ready(func():return weak_other.get_ref()==null,"Layout fixture removed"):return false
	await shot(prefix+"-minimized")
	if not await click(chip.stop_button):return false
	if not check(await Wait.settle(self,world),"Independent chip stop settles"):return false
	if not await ready(func():return not chip.visible,"Stop removes running chip"):return false
	if not check(not menu.visible and not backend_node.quest_auto.running,"Chip stop never opens helper"):return false
	await shot(prefix+"-stopped")
	if remote:
		if not await begin():return false
		menu.close_menu()
		var original_step:Dictionary=backend_node.quest_auto.step.duplicate(true)
		world.link.close()
		if not await ready(func():return backend_node.quest_auto.detached,"Real disconnect preserves server intent"):return false
		var before:Dictionary=backend_node.session.snapshot()
		backend_node.quest_auto.tick(backend_node,45.0)
		if not check(backend_node.quest_auto.running and backend_node.session.snapshot()==before,"Disconnected intent safely waits beyond landing timeout"):return false
		world.link.connect_now()
		if not await ready(func():return world.link.online and not backend_node.quest_auto.detached,"Existing UI reconnects and confirms authority position"):return false
		if not check(await Wait.settle(self,world) and backend_node.quest_auto.step==original_step,"Existing UI preserves the same step"):return false
		await shot(prefix+"-live-reconnected")
		world.link.close()
		if not await ready(func():return backend_node.quest_auto.detached,"Second disconnect before page reload"):return false
		world.music.stop();world.effect.stop();world.queue_free()
		if not await ready(func():return not is_instance_valid(world),"Old UI destroyed like refresh"):return false
		if not await create_world():return false
		if not await ready(func():return not backend_node.quest_auto.detached,"Reload reports actual server location and reattaches"):return false
		chip=world.find_child("QuestAutoChip",true,false)
		if not await ready(func():return chip.visible,"Reload discovers running task without opening helper"):return false
		if not check(backend_node.quest_auto.quest_id==11 and backend_node.quest_auto.step==original_step,"Reload retains same intent and current step"):return false
		await shot(prefix+"-reconnected")
		if not await click(chip.stop_button):return false
		if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running and not world.quest_helper_menu.visible,"Reconnected chip stops without opening"):return false
	world.music.stop();world.effect.stop()
	if remote:world.link.close()
	world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"World disposed"):return false
	if remote:server_node.stop();server_node.queue_free();backend_node.queue_free()
	return true
