extends SceneTree
## Production character-menu entry and lifecycle; no real player save.
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.unfocusable=true;root.position=Vector2i(-10000,-10000)
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false;root.add_child(game)
	await Wait.until(self,func():return game.adventure_menu!=null and not game.data.is_empty())
	var menu=game.adventure_menu
	game.show_adventure_menu("status")
	var entry=menu.panel.get_node_or_null("QuickTransmigration")
	check(entry!=null and not entry.disabled,"ordinary player sees quick rebirth beside character points")
	entry.pressed.emit();await process_frame
	var view=menu.quick_transmigration_menu
	check(is_instance_valid(view) and view.live,"production menu opens independent quick rebirth overlay")
	menu.rebuild()
	check(menu.quick_transmigration_menu==view and menu.get_child(menu.get_child_count()-1)==view,"profile-driven menu rebuild preserves overlay above panel")
	game.close_adventure_menu();await process_frame
	check(not is_instance_valid(menu.quick_transmigration_menu),"closing parent closes quick rebirth overlay")
	game.show_adventure_menu("status");menu.open_quick_transmigration()
	menu.open_menu("inventory");await process_frame
	check(not is_instance_valid(menu.quick_transmigration_menu),"switching menu closes quick rebirth overlay")
	game.music.stop();game.effect.stop();game.queue_free();await process_frame
	print("QUICK TRANSMIGRATION ENTRY: %d failures"%failures);quit(1 if failures else 0)
