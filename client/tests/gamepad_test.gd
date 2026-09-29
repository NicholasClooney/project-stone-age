extends SceneTree
## Plays with simulated controller events only: walking, menus, paging,
## dialogue and a battle command, without any mouse hover.
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func press(button: JoyButton) -> void:
	for pressed in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func frames(count: int = 3) -> void:
	for i in range(count):await process_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await frames()
	var pad = game.gamepad
	check(InputMap.action_has_event("north",_button(JOY_BUTTON_DPAD_UP)) and InputMap.action_has_event("ui_accept",_button(JOY_BUTTON_A)),"D-pad walks and A confirms through the existing actions")

	var start: Vector2i = game.cell
	var hold := InputEventJoypadButton.new();hold.button_index = JOY_BUTTON_DPAD_DOWN;hold.pressed = true
	Input.parse_input_event(hold)
	for i in range(40):await physics_frame
	hold = hold.duplicate();hold.pressed = false
	Input.parse_input_event(hold)
	for i in range(120):
		if not game.moving:break
		await physics_frame
	check(game.cell!=start,"holding the D-pad walks in the world")

	game.session.grant_starter_pets()
	await press(JOY_BUTTON_X)
	check(game.adventure_menu.visible and game.adventure_menu.kind=="status","X opens the status menu")
	await frames()
	# The 属性 bars (PlayerElements) are the status window's only live control.
	var status_controls: Array = pad.candidates(game.adventure_menu).map(func(control): return str(control.name))
	check(status_controls==["PlayerElements"],"disabled allocation arrows are never highlighted")
	await press(JOY_BUTTON_B)
	check(not game.adventure_menu.visible,"B closes the menu")

	for i in range(8):game.session._profile.pets.append(game.session._profile.pets[0].duplicate(true))
	game.sync_state()
	await press(JOY_BUTTON_Y)
	await frames()
	check(game.adventure_menu.visible and game.adventure_menu.kind=="pets","Y opens the pet menu")
	check(pad.panel()==game.adventure_menu and pad.target!=null,"menus get a controller highlight without hovering")
	var first: Control = pad.target
	await press(JOY_BUTTON_DPAD_DOWN)
	await press(JOY_BUTTON_DPAD_RIGHT)
	check(pad.target!=null and pad.target!=first,"D-pad moves the highlight between controls")
	var page_before: int = game.adventure_menu.pet_page
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	await frames()
	check(game.adventure_menu.pet_page!=page_before,"RB turns to the next page of pets")
	await press(JOY_BUTTON_B)

	game.dev_go_villager()
	for i in range(400):
		if game.dialogue.visible:break
		await physics_frame
	if not game.dialogue.visible:
		await press(JOY_BUTTON_A)
		for i in range(400):
			if game.dialogue.visible:break
			await physics_frame
	check(game.dialogue.visible,"A reaches and talks to the villager")
	await frames()
	pad.target = game.dialogue.find_child("ConfirmDialogue",true,false)
	await press(JOY_BUTTON_A)
	await frames()
	check(not game.dialogue.visible,"A on the highlighted confirm button closes the dialogue")

	game.load_area_id(100,Vector2i(637,493))
	await frames()
	check(game.begin_battle(false,1),"battle fixture opens")
	for i in range(200):
		if not game.battle_view.is_animating():break
		game.battle_view._process(0.2)
	await frames()
	var options: Array = pad.candidates(game.battle_view)
	check(pad.panel()==game.battle_view and options.size()>=4,"battle commands are reachable with the controller")
	var turn: int = int(game.battle_session.snapshot().turn)
	for option in options:
		if option is TextureButton and str(option.get_meta("action",""))=="attack":pad.target = option
	await press(JOY_BUTTON_A)
	game.battle_view._process(0.3)
	await frames()
	for option in pad.candidates(game.battle_view):
		if str(option.name).begins_with("EnemyTarget"):pad.target = option;break
	check(str(pad.target.name).begins_with("EnemyTarget"),"enemy targets are selectable after choosing a command")
	await press(JOY_BUTTON_A)
	await frames(5)
	check(int(game.battle_session.snapshot().turn)>turn or not game.battle_session.snapshot().active,"a battle command and target can be chosen with A")

	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("GAMEPAD: %d failures" % failures)
	quit(1 if failures else 0)

func _button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	return event
