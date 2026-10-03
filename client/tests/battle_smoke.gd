extends SceneTree
var game
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	print(("PASS: " if value else "FAIL: ")+label)
	if not value: failures += 1
func tick(count: int = 2) -> void:
	for i in range(count): await process_frame
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await tick()
	game.set_zoom(0.6)
	game.walk_to_exit()
	check(not game.path.is_empty(),"original west exit reachable from Samgir spawn")
	for i in range(250):
		game._physics_process(1.0)
		if int(game.data.map_id)==100:break
	while game.area_transition_busy:await process_frame
	await tick()
	check(int(game.data.map_id)==100 and game.display_cell().x==637 and game.display_cell().y in [491,492,493,494],"original portal reaches verified wilderness coordinates")
	check(is_equal_approx(game.camera.zoom.x,0.6),"selected zoom survives map transitions")
	check(not game.is_walkable(Vector2i.ZERO),"ocean boundary stays blocked")
	game.classic_hud.toggle_map()
	await tick()
	check(game.classic_hud.map_coordinates.text=="637","map coordinates show original world coordinates")
	game.classic_hud.toggle_map()
	# This suite fixes the prototype foe to verify battle choreography; ordinary
	# walking/region selection is covered by wild_encounter_integration_test.
	check(game.begin_battle(false,1),"prototype encounter opens battle and pauses exploration")
	await tick()
	var before: Vector2i = game.cell
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R; key.keycode = KEY_R; key.pressed = true
	root.push_input(key,true)
	await tick()
	check(game.cell==before and int(game.data.map_id)==100,"reset key cannot bypass battle")
	check(game.music.stream.resource_path.get_file().get_basename()=="sabgm_b0","original battle BGM selected")
	game.toggle_mute()
	check(game.music.volume_db<=-80,"mute persists during battle")
	game.toggle_mute()
	while game.battle_view.is_animating():await process_frame
	game.battle_view._request_action("defend")
	game.battle_view._request_action("attack")
	check(game.battle_session.snapshot().turn==1,"animation feedback prevents double commands")
	while game.battle_view.is_animating():await process_frame
	check(game.effect.stream.resource_path.ends_with("sae_23.wav"),"original enemy attack frame plays verified sound")
	check(game.battle_session.snapshot().turn==1,"UI command reaches local authority")
	for i in range(10):
		if not game.battle_session.snapshot().active:break
		game.battle_action("attack")
	check(game.battle_session.snapshot().outcome=="win","battle can be won")
	while game.battle_view.is_animating():game.battle_view._process(0.1)
	game.return_from_battle()
	check(not game.battle_view.visible and not game.paused_input and game.cell==before,"victory returns to same wilderness position")
	check(await preload("res://tests/support/wait.gd").until(self,func():return game.music.stream==game.exploration_music()),"exploration BGM restored after battle audio")
	check(game.field_steps==0,"return resets exploration step counter")
	game.session.heal()
	game.begin_battle()
	for i in range(3):game.battle_action("escape")
	check(game.battle_session.snapshot().outcome=="escaped","escape provides a reliable exit")
	while game.battle_view.is_animating():game.battle_view._process(0.1)
	game.return_from_battle()
	game.session.heal()
	game.session._profile.player.hp=1
	game.begin_battle(false,1)
	for i in range(60):game.battle_action("defend")
	check(game.battle_session.snapshot().outcome=="defeat","defeat outcome supported")
	game.checkpoint()
	check(game.session.snapshot().location.map_id==1000,"saving at defeat screen preserves safe village recovery")
	while game.battle_view.is_animating():game.battle_view._process(0.1)
	game.return_from_battle()
	while game.area_transition_busy:await process_frame
	await tick()
	check(int(game.data.map_id)==1000 and game.cell==game.SPAWN and not game.paused_input,"defeat recovers safely at Samgir")
	check(game.npc_data.name=="村民","village NPC restored after map changes")
	game.switch_area(true,Vector2i(45,45))
	game.walk_to_exit()
	for i in range(5):game._physics_process(1.0)
	while game.area_transition_busy:await process_frame
	await tick()
	check(int(game.data.map_id)==1000,"original return portal restores village")
	game.music.stop(); game.effect.stop()
	await create_timer(0.2).timeout
	game.queue_free(); await tick()
	quit(1 if failures else 0)
