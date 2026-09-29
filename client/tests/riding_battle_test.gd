extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.battle_effects.set_process(false)
	var authority = load("res://server/battle_session.gd").new()
	var mount := {"name":"金虎","sprite":100330,"hp":100,"max_hp":100,"attack":20,"defence":20,"speed":20}
	var state: Dictionary = authority.start_battle({"player_hp":100,"player_max_hp":100,"player_attack":10,"player_defence":10,"player_speed":10,"enemy_max_hp":1000,"enemy_attack":1,"pets":[mount],"active_pet":-1,"ride_pet_index":0,"ride_pet":mount,"mounted_sprite":101006})
	view.open_battle(state)
	for i in range(240): view._process(1.0/60.0)
	check(str(view.actors[0].character_id) == "101006","battle loads original combined tiger rider")
	check(view.riding_hp_bar.visible and view.riding_hp_bar.position == Vector2(20,25),"native mount health bar offsets match original")
	check(view.impact_sound(0) == 254,"native claw marker selects original sound254")
	check(view.actors[0].animations.has("0_3"),"mounted actor has original attack animation")
	check(not view.actors[2].enabled,"riding pet does not appear twice as battle companion")
	view.pending_action = "attack"
	view.show_state(authority.submit_action("attack"))
	check(view.actors[0].cues.any(func(cue): return int(cue.action)==0),"mounted combat queues native attack action")
	for i in range(150):
		view._process(1.0/60.0)
		view.battle_effects._process(1.0/60.0)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/original-gold-tiger-battle.png")
	view.queue_free()
	await process_frame
	await process_frame
	print("Riding battle failures: ",failures)
	quit(1 if failures else 0)
