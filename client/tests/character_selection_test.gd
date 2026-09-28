extends SceneTree
var failures := 0
var game
func check(ok: bool, message: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok:failures += 1
func frames(count: int = 2) -> void:
	for i in range(count):await process_frame
func _initialize() -> void:call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await frames()
	check(game.character_catalog.choices.size() >= 12,"expanded source-validated appearances available")
	# Web: each character's art is its own pack, and the chooser draws them all.
	var packs = game.asset_packs
	var saved := [packs.enabled,packs.index.duplicate(true),packs._mounted.duplicate(),packs.base_url]
	packs.enabled = true
	# Nothing listens there: the fake downloads fail quietly.
	packs.base_url = "http://127.0.0.1:9/"
	packs.index = {"packs":{},"characters":{}}
	for choice in game.character_catalog.choices:
		var pack_name := "char-%s" % str(choice.id)
		packs.index.packs[pack_name] = {"file":pack_name+".pck","bytes":1,"sha256":"test"}
		packs.index.characters[str(choice.id)] = pack_name
	packs._mounted = {}
	check(game.character_selection.character_packs().size()==game.character_catalog.choices.size(),"the chooser needs the art pack of every character")
	game.character_selection.open_menu()
	check(not game.character_selection.visible,"the chooser waits while character art is still downloading")
	for pack_name in packs.index.packs:packs._mounted[pack_name] = true
	game.character_selection.open_menu()
	check(game.character_selection.visible,"the chooser opens once every character's art is available")
	game.character_selection.close_menu()
	# Drop the fake downloads the first attempt queued before restoring desktop mode.
	for request in packs._active.keys():if is_instance_valid(request):request.cancel_request();request.queue_free()
	packs._queued.clear();packs._active.clear();packs._attempts.clear();packs._failed.clear();packs._waiters.clear()
	packs.enabled = saved[0];packs.index = saved[1];packs._mounted = saved[2];packs.base_url = saved[3]
	await frames()
	game.change_character()
	await frames()
	check(game.character_selection.visible and game.paused_input,"developer chooser pauses field movement")
	var before_choice: Dictionary = game.session.snapshot()
	for key in [KEY_H,KEY_H,KEY_R]:
		var event := InputEventKey.new()
		event.keycode=key;event.physical_keycode=key;event.pressed=true
		root.push_input(event,true)
	check(game.paused_input and not game.help.visible and game.session.snapshot()==before_choice,"chooser blocks game shortcuts behind preview window")
	var chosen: String = str(game.character_catalog.choices[-1].id)
	game.character_selection.buttons[chosen].pressed.emit()
	await frames()
	check(game.player.character_id == chosen and game.session.snapshot().character_id == chosen,"preview button selects and persists exact original appearance")
	var actor = game.character_selection.buttons[chosen].get_child(0)
	var old_elapsed: float = actor.elapsed
	await create_timer(0.15).timeout
	check(actor.elapsed > old_elapsed and actor.sprite.texture != null,"chooser previews animate original frames")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/stone-age-character-selection.png")
	game.character_selection.close_menu()
	check(not game.paused_input,"closing chooser restores movement")
	check(game.load_area_id(1002,Vector2i(11,15)),"enter original shop")
	await frames()
	check(game.player.character_id == chosen,"appearance survives map rebuild")
	var path := "user://character-selection-test.json"
	check(game.session.save_game(path),"selected appearance saves")
	var restored = preload("res://server/game_session.gd").new()
	check(restored.load_game(path) and restored.snapshot().character_id == chosen,"selected appearance restores")
	check(not restored.set_character("100001") and not restored.set_character("999999"),"weapon-only and invalid appearance IDs rejected")
	var old := restored.snapshot()
	old.erase("character_id")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old));file.close()
	check(restored.load_game(path) and restored.snapshot().character_id == "100000","older saves migrate to original default")
	game.session._profile.inventory.club = 1
	game.session.equip_item()
	game.load_area_id(100,Vector2i(637,493))
	check(game.begin_battle(false,1),"battle starts with selected appearance")
	game.change_character("100000")
	check(game.player.character_id == chosen and not game.session.set_character("100000"),"character switch blocked during battle in UI and authority")
	var expected: String = game.battle_view.manifest.equipment_variants.club[chosen]
	check(game.battle_view.actors[0].character_id == expected,"selected appearance uses source-verified club battle sprite")
	game.set_process(false);game.set_physics_process(false)
	game.battle_view.set_process(false)
	game.music.stop();game.effect.stop()
	game.queue_free();await frames(3)
	await create_timer(0.3).timeout
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("CHARACTER SELECTION: %d failures" % failures)
	quit(1 if failures else 0)
