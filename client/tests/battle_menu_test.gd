extends SceneTree
var failures := 0
var submitted: Array[String] = []
var pet_commands: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok: failures += 1
func run() -> void:
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	view.action_requested.connect(func(action: String): submitted.append(action))
	view.pet_command_requested.connect(func(command: String): pet_commands.append(command))
	await process_frame
	var state := {"active":true,"player_hp":80,"player_max_hp":100,"enemy_hp":30,"enemy_max_hp":30,"turn":0,"potions":2}
	view.open_battle(state)
	view._request_action("attack")
	check(submitted.is_empty(),"attack waits for target selection")
	view.select_target(0)
	check(submitted.is_empty(),"attack rejects friendly target")
	view.cancel_selection()
	view.select_target(1)
	check(submitted.is_empty(),"cancel clears queued attack without fleeing")
	view._request_action("capture")
	view.select_target(1)
	check(submitted==["capture"],"capture submits only after enemy click")
	view._request_action("item")
	check(view.choice_panel.get_child_count()>0,"original item picker opens")
	for child in view.choice_panel.get_children():
		if child is Button: child.pressed.emit()
	check(view.selected_action=="item_target","potion slot selects item for targeting")
	view.select_target(1)
	check(submitted.size()==1,"potion rejects enemy target")
	view.select_target(0)
	check(submitted.back()=="item","potion submits after player target")
	submitted = ["capture"]
	view.cancel_selection()
	state.pet = {"species":"wooli","name":"乌力","hp":30,"max_hp":30}
	state.pet_hp = 30
	view.open_battle(state)
	view._request_action("attack")
	view.select_target(1)
	check(view.command_phase=="pet" and submitted.size()==1,"player command waits for pet command")
	view.selected_action = "pet_skill"
	view.select_target(1)
	check(pet_commands==["skill"] and submitted==["capture","attack"],"pet command precedes turn submission")
	view.open_battle(state)
	view._request_action("attack")
	view.select_target(1)
	view.cancel_selection()
	check(view.command_phase=="player" and view.queued_player_action.is_empty(),"pet menu cancel returns to player phase")
	for button in view.commands:
		check(button.texture_hover==button.texture_normal,"hover does not depress original button")
	# Authority order is player -> enemy -> slower guarding pet.
	var next := state.duplicate(true)
	next.turn = 1
	next.turn_order = ["player","enemy","pet"]
	next.last_pet_command = "defend"
	next.pet_hp = 20
	view.pending_action = "attack"
	view.show_state(next)
	check(is_equal_approx(view.feedback_until-view.elapsed,1.5),"three acted participants lock input for ordered feedback")
	check(view.actors[1].cues.any(func(cue): return cue.action==0 and is_equal_approx(cue.at-view.elapsed,0.5)),"enemy attack follows player before slower pet")
	check(view.actors[2].cues.any(func(cue): return cue.action==10 and is_equal_approx(cue.at-view.elapsed,1.0)),"pet defence uses guard pose in authority order")
	check(view.actors[2].cues.any(func(cue): return cue.action==1 and is_equal_approx(cue.at-view.elapsed,0.75)),"enemy damage targets companion that lost HP")
	next = state.duplicate(true)
	next.turn = 2
	next.turn_order = ["enemy"]
	next.player_hp = 0
	view.show_state(next)
	check(view.actors[0].cues.any(func(cue): return cue.action==2),"zero HP player receives knockout pose")
	state.boss = true
	view.open_battle(state)
	view._process(0)
	check(view.commands[2].disabled and "无法" in view.commands[2].tooltip_text,"boss capture is disabled with explanation")
	state.boss = false
	state.can_capture = false
	view.open_battle(state)
	view._process(0)
	check(view.commands[2].disabled and "已满" in view.commands[2].tooltip_text,"full pet roster disables capture with explanation")
	state.can_capture = true
	state.player_hp = state.player_max_hp
	view.open_battle(state)
	view._request_action("item")
	for child in view.choice_panel.get_children():
		if child is Button: check(child.disabled and "体力已满" in child.tooltip_text,"full health disables potion slot with explanation")
	state.player_hp = 80
	state.potions = 0
	view.open_battle(state)
	view._request_action("item")
	for child in view.choice_panel.get_children():
		if child is Button: check(child.disabled and "已用完" in child.tooltip_text,"empty potion stock disables item slot")
	state.potions = 2
	view.open_battle(state)
	view._process(0)
	check(not view.commands[2].disabled,"ordinary battle restores capture availability")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/mvp-original-battle-menu.png")
		view._request_action("item")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/mvp-original-battle-items.png")
		view.cancel_selection()
		view.complete_player_command("attack")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/mvp-original-battle-pet.png")
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)
