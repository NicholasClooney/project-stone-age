extends SceneTree
var game
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok: failures += 1
func tick() -> void:
	await process_frame
	await process_frame
func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	root.push_input(move,true)
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
		await process_frame
func cancel() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event,true)
	await tick()
func pet_attack_button(view: Control) -> Button:
	for child in view.choice_panel.get_children():
		if child is Button and child.text=="攻击": return child
	return null
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await tick()
	# Obtain a real companion through public authority commands; no profile mutation.
	var setup_battle = load("res://server/battle_session.gd").new()
	setup_battle.start_battle(game.session.start_battle_config("wooli"))
	setup_battle.submit_action("attack")
	setup_battle.submit_action("attack")
	var captured: Dictionary = setup_battle.submit_action("capture")
	check(captured.outcome=="captured" and game.session.apply_battle_result(captured),"companion obtained through authority capture flow")
	game.session.heal()
	game.switch_area(true,Vector2i(45,45))
	await tick()
	var started: bool = game.begin_battle()
	check(started,"real world starts companion battle")
	if not started:
		game.queue_free()
		quit(1)
		return
	await tick()
	var view: Control = game.battle_view
	var start: Dictionary = game.battle_session.snapshot()
	await click(view.commands[0])
	check(view.selected_action=="attack" and game.battle_session.snapshot().turn==0,"real mouse selects original attack without consuming turn")
	await click(view.target_buttons[1])
	check(view.command_phase=="pet" and game.battle_session.snapshot().turn==0,"real enemy click enters pet phase")
	var pet_attack := pet_attack_button(view)
	check(pet_attack!=null,"original pet skill panel has attack entry")
	if pet_attack!=null:
		await click(pet_attack)
		await click(view.target_buttons[1])
	check(game.battle_session.snapshot().turn==1 and game.battle_session.snapshot().enemy_hp < start.enemy_hp,"player and pet mouse commands resolve exactly one turn")
	await click(view.commands[0])
	await click(view.target_buttons[1])
	check(game.battle_session.snapshot().turn==1,"rapid mouse clicks blocked during animation")
	await create_timer(1.6).timeout
	await click(view.commands[5])
	check(view.selected_action=="item" and view.choice_panel.get_child_count()>0,"original item button opens inventory picker")
	await cancel()
	check(view.selected_action.is_empty() and game.battle_session.snapshot().potions==start.potions,"Escape cancels item menu without consuming potion or fleeing")
	await click(view.commands[2])
	await click(view.target_buttons[1])
	check(view.command_phase=="pet" and view.queued_player_action=="capture","capture target queued before pet command")
	await cancel()
	check(view.command_phase=="player" and game.battle_session.snapshot().turn==1,"cancel pet phase preserves battle and turn")
	var cell: Vector2i = game.cell
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.physical_keycode = KEY_R
	reset.pressed = true
	root.push_input(reset,true)
	await tick()
	check(game.cell==cell and int(game.data.map_id)==100 and view.visible,"world reset key cannot bypass modal battle")
	# Finish two victories through public commands to reach the real pet skill unlock.
	for fight in range(2):
		for turn in range(15):
			if not game.battle_session.snapshot().active: break
			game.battle_action("attack")
		game.return_from_battle()
		game.session.heal()
		if fight==0: game.begin_battle()
	check(game.session.snapshot().pets[0].level>=2 and game.session.snapshot().pets[0].skill_unlocked,"pet level progression unlocks skill after victories")
	game.begin_battle()
	view = game.battle_view
	await click(view.commands[0])
	await click(view.target_buttons[1])
	var skill_available := false
	for child in view.choice_panel.get_children():
		if child is Button and child.text=="技能": skill_available = not child.disabled
	check(skill_available,"real original pet menu enables unlocked skill")
	game.music.stop()
	game.effect.stop()
	await create_timer(0.25).timeout
	game.queue_free()
	await tick()
	quit(1 if failures else 0)
