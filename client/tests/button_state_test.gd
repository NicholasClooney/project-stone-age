extends SceneTree
## world.button keeps its size and a readable label in every state. The
## engine's own disabled look has smaller margins and a near-transparent
## background, so a disabled button shrank and its label all but vanished on
## the dark panels: 自动抓极品's 停止 and 最小化 whenever no scan was running.
var failures := 0

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate();game.profile_persistence = false;root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))

	var plain: Button = game.button("停止",func():pass)
	root.add_child(plain)
	var enabled_size: Vector2 = plain.get_combined_minimum_size()
	plain.disabled = true
	check(plain.get_combined_minimum_size()==enabled_size,"a disabled world.button keeps its size")
	var disabled_style: StyleBox = plain.get_theme_stylebox("disabled")
	check(disabled_style.content_margin_left==12 and disabled_style.content_margin_top==7,"its disabled look keeps the normal margins")
	var ink: Color = plain.get_theme_color("font_disabled_color")
	check(ink.a>0.9 and ink.v>0.5,"disabled text stays readable")
	for state in ["pressed","hover_pressed"]:
		check(plain.get_theme_stylebox(state).content_margin_left==12,"the %s look keeps the margins too" % state)
	plain.queue_free()

	var hunt = game.pet_hunt_menu
	var flow = game.pet_workflow;flow.set_process(false);hunt.set_process(false)
	game.training_helper.set_process(false)
	game.backend.automation.auto_tick = false
	hunt.open_menu()
	await process_frame
	var sizes := {}
	for button in [hunt.stop_button,hunt.minimize_button]:sizes[button.name] = button.size
	check(hunt.stop_button.disabled and hunt.stop_button.text=="停止" and hunt.minimize_button.text=="最小化","idle: 停止 and 最小化 are disabled with their text")
	check(hunt.stop_button.size.x>=45 and hunt.minimize_button.size.x>=60,"idle, they are as wide as when enabled (%s)" % str(sizes))
	for locked in [true,false,true,false]:
		hunt.set_controls(locked)
		await process_frame
	var same := true
	for button in [hunt.stop_button,hunt.minimize_button]:
		if button.size!=sizes[button.name]:same = false
	check(same,"they keep their size switching between running and idle")

	hunt.apply_preset(0)
	check(flow.start_cycle(),"a find-pet cycle runs")
	hunt.on_status(game.state.automation)
	hunt.minimize()
	hunt.restore()
	hunt.on_status(game.state.automation)
	await process_frame
	check(not hunt.stop_button.disabled and hunt.stop_button.size==sizes[hunt.stop_button.name] and hunt.minimize_button.size==sizes[hunt.minimize_button.name],"after status refreshes, minimize and restore they keep size and text")
	game.backend.automation.stop_request("已手动停止")
	hunt.on_event({"kind":"hunt_stopped","reason":"已手动停止"})
	await process_frame
	check(hunt.stop_button.disabled and hunt.stop_button.size==sizes[hunt.stop_button.name],"stopped, 停止 is disabled at the same size")
	hunt.close_menu()

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("BUTTON STATE: %d failures" % failures)
	quit(1 if failures else 0)
