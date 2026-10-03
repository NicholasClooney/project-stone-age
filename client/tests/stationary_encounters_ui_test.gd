extends SceneTree
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var visual := false
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func click(control: Control):
	check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0),"real mouse target laid out")
	var point: Vector2 = control.get_global_transform_with_canvas()*(control.size/2)
	var motion := InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)
		await process_frame
func shot(name: String):
	if not visual:return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/private/tmp/stationary-render/"+name+".png")
func layout(menu):
	await process_frame
	await process_frame
	print("LAYOUT root=",root.size," viewport=",root.get_visible_rect()," menu=",menu.get_global_rect())
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(menu.get_global_rect()),"helper fits viewport")
	var scroll = menu.find_child("HelperScroll",true,false)
	check(scroll.get_h_scroll_bar().max_value<=scroll.size.x+1,"no horizontal overflow")
	for name in ["HelperNoRandomEncounters","HelperStationaryEncounters"]:
		var control = menu.find_child(name,true,false)
		check(control.size.y>=44,"touch target "+name)
func run():
	root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	visual="--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if visual:DirAccess.make_dir_recursive_absolute("/private/tmp/stationary-render")
	var b=Backend.new();root.add_child(b);b.set_process(false)
	var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
	check(server.start()==OK,"isolated port0 server")
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	var game=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	game.profile_persistence=false;game.viewer_prefs_path="user://stationary-ui.cfg";root.add_child(game)
	check(await Wait.until(self,func():return game.link.online and not game.data.is_empty()) and await Wait.settle(self,game),"remote ready")
	check(game.backend==null,"real remote viewer has no backend")
	game.random_encounters=false
	var menu=game.helper_menu
	menu.open_menu();check(await Wait.settle(self,game),"safe map status fetched")
	await layout(menu)
	check(menu.find_child("HelperNoRandomEncounters",true,false).text=="不遇敌","short no-encounter label")
	check(menu.find_child("HelperStationaryEncounters",true,false).disabled,"safe map disabled with explanation")
	await shot("390-safe")
	menu.close_menu()
	b.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	check(await Wait.until(self,func():return int(game.data.map_id)==100 and not game.area_transition_busy) and await Wait.settle(self,game),"real remote field position loaded")
	menu.open_menu();await Wait.settle(self,game)
	await click(menu.find_child("HelperViewList",true,false));await layout(menu);await shot("390-list")
	await click(menu.find_child("HelperViewGrid",true,false));await layout(menu);await shot("390-grid")
	check(game.gamepad.candidates(menu).any(func(c):return c.name=="HelperStationaryEncounters"),"gamepad retains stationary toggle")
	await click(menu.find_child("HelperNoRandomEncounters",true,false));await Wait.settle(self,game)
	check(b.session._profile.no_random_encounters,"actual remote click enables no encounters")
	await click(menu.find_child("HelperStationaryEncounters",true,false))
	check(await Wait.until(self,func():return b.stationary.running and not menu.visible) and await Wait.settle(self,game),"enable ack closes this helper")
	check(not b.session._profile.no_random_encounters,"remote toggles mutually exclusive")
	menu.open_menu();await Wait.settle(self,game)
	check(not b.stationary.running,"reopen helper stops")
	# Late ack: the real remote request has not yet reached the server; hide
	# this menu and open another before polling a frame.
	menu.stationary_ui.toggle(game,menu,true)
	menu.close_menu();game.settings_menu.open_menu()
	await Wait.settle(self,game);await Wait.settle(self,game)
	check(not b.stationary.running and game.settings_menu.visible,"late enable ack preserves later window and stops")
	game.settings_menu.close_menu()
	menu.open_menu();await Wait.settle(self,game)
	b.stationary_party_member=func():return true
	await click(menu.find_child("HelperStationaryEncounters",true,false));await Wait.settle(self,game)
	check(menu.visible and not b.stationary.running and menu.stationary_ui.feedback.contains("组队"),"server rejection leaves helper and explains party conflict")
	b.stationary_party_member=Callable()
	menu.close_menu();menu.open_menu();await Wait.settle(self,game)
	root.size=Vector2i(1280,720)
	check(await Wait.until(self,func():return menu.position.x>300 and menu.size.x==520),"desktop resize settled")
	await click(menu.find_child("HelperViewList",true,false));await layout(menu);check(menu.view=="list","actual desktop list click");await shot("1280-list")
	await click(menu.find_child("HelperViewGrid",true,false));await layout(menu);check(menu.view=="grid","actual desktop grid click");await shot("1280-grid")
	await click(menu.find_child("HelperStationaryEncounters",true,false))
	check(await Wait.until(self,func():return b.stationary.running and not menu.visible),"re-enable before blocked menu")
	var reference=Backend.new()
	reference.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	b.encounter_rng.seed=918;b.encounter_catalog.pressure=0
	reference.encounter_rng.seed=918
	b.stationary.lease=100
	for i in range(100):
		if b.battle_open:break
		b._process(0.5)
		reference.handle({"type":"field_step","map_id":100,"cell":[637,493],"encounter":true})
	check(b.battle_open and b.encounter_rng.state==reference.encounter_rng.state and b.encounter_catalog.pressure==reference.encounter_catalog.pressure,"remote run uses exact ordinary RNG and pressure")
	check(await Wait.until(self,func():return game.battle_view.visible) and await Wait.settle(self,game),"server encounter opens real remote battle view")
	check(JSON.parse_string(JSON.stringify(game.battle_session.snapshot().enemies))==JSON.parse_string(JSON.stringify(reference.battle_state.enemies)),"remote receives exact source troop across JSON numeric types")
	reference.free()
	b.battle._config.player_attack=100000;b.battle._config.player_defence=100000
	for i in range(100):
		if not b.battle.snapshot().active:break
		var target:=0
		for j in range(b.battle._state.enemies.size()):
			if b.battle._state.enemies[j].hp>0:target=j;break
		game.link.request({"type":"battle_command","action":"attack","target":target})
		await Wait.settle(self,game)
	check(b.battle.snapshot().outcome=="win" and b.stationary.saved_win,"real remote commands win and commit own battle")
	game.link.request({"type":"battle_close"});await Wait.settle(self,game)
	b._process(0.01)
	check(b.stationary.running and b.stationary.battle_id.is_empty(),"remote successful close resumes encounters")
	game.settings_menu.open_menu();await Wait.settle(self,game);await Wait.settle(self,game)
	check(not b.stationary.running,"blocking settings stops through link")
	game.settings_menu.close_menu();menu.open_menu();await Wait.settle(self,game)
	menu.stationary_ui.toggle(game,menu,true)
	game.link.close()
	await process_frame
	b.stationary.tick(b,5.1)
	check(not b.stationary.running,"disconnect during enable cannot leave an orphan run")
	game.music.stop();game.effect.stop();game.queue_free();server.stop();server.queue_free();b.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://stationary-ui.cfg"))
	print("STATIONARY UI: %d failures"%failures)
	quit(1 if failures else 0)
