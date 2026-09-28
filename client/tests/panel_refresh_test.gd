extends SceneTree
## Panels rebuilt for new backend data keep the player's scroll position.
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	game.session.grant_starter_pets()
	var pet: Dictionary = game.session._profile.pets[0]
	var storage: Array = []
	for i in range(20):
		var copy: Dictionary = pet.duplicate(true)
		copy.pet_id = "scroll-%d" % i
		copy.name = "仓库宠物%d" % i
		storage.append(copy)
	game.session._profile.pet_storage = storage
	game.sync_state()
	var menu = game.adventure_menu
	game.show_adventure_menu("pets")
	menu.pet_storage_open = true
	menu.pet_view = "storage"
	menu.rebuild()
	await process_frame
	await process_frame
	var scrolls: Array = game._scroll_areas(menu)
	check(scrolls.size()==1,"the warehouse has one scroll area")
	var scroll: ScrollContainer = scrolls[0]
	check(scroll.get_v_scroll_bar().max_value > scroll.size.y,"the warehouse list is long enough to scroll")
	scroll.scroll_vertical = 300
	await process_frame
	var scrolled: int = scroll.scroll_vertical
	check(scrolled > 0,"the player scrolls down the warehouse")

	game.rebuild_keeping_scroll(menu)
	var rebuilt: ScrollContainer = game._scroll_areas(menu)[0]
	check(rebuilt!=scroll,"the panel was rebuilt with new controls")
	await process_frame
	await process_frame
	check(rebuilt.scroll_vertical==scrolled,"the rebuilt warehouse keeps the scroll position")

	rebuilt.scroll_vertical = 0
	await process_frame
	game.rebuild_keeping_scroll(menu)
	await process_frame
	await process_frame
	check(game._scroll_areas(menu)[0].scroll_vertical==0,"a list at the top stays at the top")

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("PANEL REFRESH: %d failures" % failures)
	quit(1 if failures else 0)
