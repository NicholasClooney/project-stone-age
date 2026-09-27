extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+text)
	if not ok:failures += 1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	var log = game.changelog_menu
	check(log.history.count > 0 and log.history.version == ProjectSettings.get_setting("application/config/version"),"game version matches feat/fix changelog")
	check(log.history.entries[0].version == log.history.version,"latest update appears first")
	var before: Dictionary = game.session.snapshot()
	log.open_menu()
	check(log.visible and game.paused_input,"changelog opens and pauses walking")
	for key in [KEY_H,KEY_H,KEY_R,KEY_TAB,KEY_E,KEY_X]:
		var event := InputEventKey.new()
		event.physical_keycode=key;event.keycode=key;event.pressed=true
		root.push_input(event,true)
	check(log.visible and game.paused_input and not game.help.visible and game.session.snapshot()==before,"game shortcuts cannot mutate or unpause behind changelog")
	check(log.text_area.get_parsed_text().contains(log.history.entries[0].title),"readable release details rendered")
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/stone-age-changelog.png")
	var escape := InputEventKey.new()
	escape.keycode=KEY_ESCAPE;escape.physical_keycode=KEY_ESCAPE;escape.pressed=true
	root.push_input(escape,true)
	check(not log.visible and not game.paused_input,"Escape closes log and restores play")
	game.set_process(false);game.set_physics_process(false)
	game.music.stop();game.effect.stop()
	game.music.stream=null;game.effect.stream=null
	game.queue_free()
	await process_frame;await process_frame
	await create_timer(0.5).timeout
	quit(1 if failures else 0)
