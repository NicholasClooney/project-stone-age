extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Panels refreshed for new backend data keep the player's scroll position.
const Warehouse=preload("res://tests/support/warehouse.gd")
const Wait=preload("res://tests/support/wait.gd")
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
	check(rebuilt==scroll,"the warehouse refresh reuses its scroll controls")
	await process_frame
	await process_frame
	check(rebuilt.scroll_vertical==scrolled,"the refreshed warehouse keeps the scroll position")

	# Use real session operations after fixture construction. An open species
	# popup defers a push but closing it must apply it without another push.
	var picker: OptionButton=menu.panel.find_child("StorageSpecies",true,false)
	picker.show_popup()
	check(picker.get_popup().visible,"warehouse species popup is open")
	check(game.session.retrieve_pet_by_id("scroll-0"),"retrieve removes a real stored UID")
	game.sync_state();game.rebuild_keeping_scroll(menu)
	check(menu.panel.find_child("StorageRow_scroll-0",true,false)!=null,"an open popup defers the warehouse content refresh")
	picker.get_popup().hide()
	check(await Wait.until(self,func():return menu.panel.find_child("StorageRow_scroll-0",true,false)==null and Warehouse.matches(menu,game.session.snapshot())),"closing the popup applies deleted UID, count, stats and capacity without a further push")
	check(game._scroll_areas(menu)[0]==scroll and scroll.scroll_vertical==scrolled,"deferred reconciliation retains the scroll node and position")
	var carried: Array=game.session.snapshot().pets
	var index: int=carried.size()-1
	check(game.session.gm_raise_level(index,12),"real session changes retrieved pet stats")
	check(game.session.store_pet(index),"store returns the changed UID")
	game.sync_state();game.rebuild_keeping_scroll(menu)
	check(await Wait.until(self,func():return Warehouse.matches(menu,game.session.snapshot()) and menu.panel.find_child("StorageRow_scroll-0",true,false)!=null),"newly stored UID shows updated level, all stat cells, tooltip, count and actions")

	rebuilt.scroll_vertical = 0
	await process_frame
	game.rebuild_keeping_scroll(menu)
	await process_frame
	await process_frame
	check(game._scroll_areas(menu)[0].scroll_vertical==0,"a list at the top stays at the top")

	# The 同种比较 view: the player's own actions (sort, checkboxes) rebuild the
	# menu directly and must keep the place in the list too.
	menu.pet_storage_open = false
	menu.pet_view = "list"
	menu.pet_compare_subject = game.session.snapshot().pets[0].duplicate(true)
	menu.pet_compare_open = true
	menu.rebuild()
	await process_frame
	await process_frame
	var compare: ScrollContainer = game._scroll_areas(menu)[0]
	check(compare.get_v_scroll_bar().max_value > compare.size.y,"the comparison list is long enough to scroll")
	compare.scroll_vertical = 200
	await process_frame
	var compared: int = compare.scroll_vertical
	menu.rebuild()
	await process_frame
	await process_frame
	check(compared > 0 and game._scroll_areas(menu)[0].scroll_vertical==compared,"a rebuild from the player's own action keeps the comparison scroll")
	menu.pet_compare_page += 1
	menu.rebuild()
	await process_frame
	await process_frame
	check(game._scroll_areas(menu)[0].scroll_vertical==0,"turning the page starts at the top")
	menu.pet_compare_page = 0
	menu.rebuild()
	await process_frame
	game._scroll_areas(menu)[0].scroll_vertical = 200
	await process_frame
	game.close_adventure_menu()
	game.show_adventure_menu("pets")
	menu.pet_compare_open = true
	menu.rebuild()
	await process_frame
	await process_frame
	check(game._scroll_areas(menu)[0].scroll_vertical==0,"reopening the menu starts at the top")

	# A number box that merely holds focus (after a click on it or its arrows)
	# must not freeze the panel: new pets have to appear in 同种比较.
	game.close_adventure_menu()
	game.show_adventure_menu("pets")
	menu.pet_compare_open = true
	menu.rebuild()
	await process_frame
	var threshold: SpinBox = menu.find_child("CompareThresholdValue",true,false)
	check(threshold != null,"the comparison view has its threshold number box")
	threshold.get_line_edit().grab_focus()
	game._last_typing_msec = -100000
	var deferred: bool = game.refresh_open_panels()
	check(not deferred and not menu.is_ancestor_of(threshold),"a focused but idle number box does not stop the panel refreshing")
	var fresh: SpinBox = menu.find_child("CompareThresholdValue",true,false)
	fresh.get_line_edit().grab_focus()
	game._last_typing_msec = Clock.ticks_msec()
	check(game.refresh_open_panels() and menu.is_ancestor_of(fresh),"while the player is typing the panel waits")
	game._last_typing_msec = -100000

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	print("PANEL REFRESH: %d failures" % failures)
	quit(1 if failures else 0)
