extends SceneTree
class DefeatWorld:
	extends Node
	var returns := 0
	var adventure_menu: Control
	func return_from_battle() -> void: returns += 1
var failures := 0
var submitted: Array[String] = []
var pet_commands: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok: failures += 1
func settle(view: Control) -> void:
	view._process(maxf(0.0,view.feedback_until-view.elapsed)+0.01)
func run() -> void:
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	view.action_requested.connect(func(action: String): submitted.append(action))
	view.pet_command_requested.connect(func(command: String): pet_commands.append(command))
	await process_frame
	var state := {"active":true,"player_hp":80,"player_max_hp":100,"enemy_hp":30,"enemy_max_hp":30,"turn":0,"potions":2}
	view.open_battle(state)
	settle(view)
	check(view.selected_action=="attack" and submitted.is_empty(),"new battle defaults to attack targeting without submitting")
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
	settle(view)
	view._request_action("attack")
	view.select_target(1)
	check(view.command_phase=="pet" and submitted.size()==1,"player command waits for pet command")
	view.selected_action = "pet_skill"
	view.select_target(1)
	check(pet_commands==["skill"] and submitted==["capture","attack"],"pet command precedes turn submission")
	check(view.last_pet_command=="skill","completed pet skill selection is remembered")
	view.open_battle(state)
	settle(view)
	view._request_action("attack")
	view.select_target(1)
	check(view.selected_action=="pet_attack","unavailable remembered pet skill safely falls back to attack targeting")
	view.cancel_selection()
	check(view.command_phase=="pet" and view.selected_action.is_empty(),"cancel remembered pet target reopens skill picker")
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
	check(view.feedback_until-view.elapsed>2.0,"three acted participants lock input through travel and strikes")
	check(view.actors[1].motions[0].at>view.actors[0].motions[1].end,"enemy approaches only after player returns home")
	check(view.actors[2].cues.any(func(cue): return cue.action==10 and cue.at>view.actors[1].motions[1].end),"pet defence uses guard pose after enemy returns")
	check(view.actors[2].cues.any(func(cue): return cue.action==1 and cue.at>view.actors[1].motions[0].end),"enemy strike damages companion after approach")
	next = state.duplicate(true)
	next.turn = 2
	next.turn_order = ["enemy"]
	next.player_hp = 0
	view.show_state(next)
	check(view.actors[0].cues.any(func(cue): return cue.action==2),"zero HP player receives knockout pose")
	settle(view)
	check(Vector2(view.actors[0].point).is_equal_approx(view.actors[0].home),"attacker returns to exact formation position")
	var entrance := state.duplicate(true)
	view.open_battle(entrance)
	check(view.is_animating() and Vector2(view.actors[0].point).distance_to(view.actors[0].home)>300,"original diagonal entrance begins off formation")
	view._request_action("attack")
	check(view.selected_action=="attack" and view.is_animating(),"entrance keeps default attack pending until walk-in and menu slide finish")
	settle(view)
	check(Vector2(view.actors[0].point).is_equal_approx(view.actors[0].home) and is_zero_approx(view.command_panel.position.x),"walk-in and sliding menu settle at original endpoints")
	view._request_action("capture")
	var remember_state := state.duplicate(true)
	remember_state.turn = 3
	view.show_state(remember_state)
	settle(view)
	check(view.selected_action=="capture","next round restores last player capture target selection")
	view._request_action("item")
	remember_state.turn = 4
	view.show_state(remember_state)
	settle(view)
	check(view.selected_action=="attack" and view.choice_panel.get_child_count()==0,"consumable selection is not replayed next round")
	state.boss = true
	view.open_battle(state)
	settle(view)
	view._process(0)
	check(view.commands[2].disabled and "无法" in view.commands[2].tooltip_text,"boss capture is disabled with explanation")
	state.boss = false
	state.can_capture = false
	view.open_battle(state)
	settle(view)
	view._process(0)
	check(view.commands[2].disabled and "已满" in view.commands[2].tooltip_text,"full pet roster disables capture with explanation")
	state.can_capture = true
	state.player_hp = state.player_max_hp
	view.open_battle(state)
	settle(view)
	view._request_action("item")
	for child in view.choice_panel.get_children():
		if child is Button: check(child.disabled and "体力已满" in child.tooltip_text,"full health disables potion slot with explanation")
	state.player_hp = 80
	state.potions = 0
	view.open_battle(state)
	settle(view)
	view._request_action("item")
	for child in view.choice_panel.get_children():
		if child is Button: check(child.disabled and "已用完" in child.tooltip_text,"empty potion stock disables item slot")
	state.potions = 2
	view.open_battle(state)
	settle(view)
	view._process(0)
	check(not view.commands[2].disabled,"ordinary battle restores capture availability")
	await process_frame
	check(is_equal_approx(view.hp_fills[0].size.x,32.0),"original 40-pixel HP meter shows 80 percent health")
	check(view.hp_bars[0].position==Vector2(view.actors[0].point)+Vector2(0,-80),"original HP meter follows 80 pixels above actor")
	check(not "HP" in view.actor_labels[0].text,"names no longer duplicate numeric HP overlay")
	var health_turn := state.duplicate(true)
	health_turn.turn = 50
	health_turn.turn_order = ["player","enemy","pet"]
	health_turn.last_pet_command = "attack"
	health_turn.enemy_hp = 12
	health_turn.player_hp = 72
	health_turn.turn_frames = [{"actor":"player","player_hp":80,"enemy_hp":18,"pet_hp":30},{"actor":"enemy","player_hp":72,"enemy_hp":18,"pet_hp":30},{"actor":"pet","player_hp":72,"enemy_hp":12,"pet_hp":30}]
	view.pending_action = "attack"
	view.show_state(health_turn)
	check(view.displayed_hp[1]==30,"HP does not jump to resolved result before strike")
	var first_hit := float(view.hp_cues[0].at)
	view._process(first_hit-view.elapsed+0.001)
	check(view.displayed_hp[1]==18 and view.displayed_hp[0]==80,"first strike applies its exact authoritative HP snapshot")
	settle(view)
	check(view.displayed_hp==[72,12,30],"all overhead HP meters settle to final authoritative values")
	view.open_battle(state)
	settle(view)
	var fake := DefeatWorld.new()
	root.add_child(fake)
	fake.adventure_menu = Control.new()
	fake.add_child(fake.adventure_menu)
	view.world = fake
	var selected_before: String = view.selected_action
	view._request_action("capture")
	view.select_target(1)
	check(view.selected_action==selected_before and view.command_phase=="player","system modal blocks battle commands behind it")
	fake.adventure_menu.hide()
	var defeat := state.duplicate(true)
	defeat.turn = 60
	defeat.active = false
	defeat.outcome = "defeat"
	defeat.player_hp = 0
	defeat.turn_order = ["enemy"]
	defeat.turn_frames = [{"actor":"enemy","player_hp":0,"enemy_hp":30,"pet_hp":30}]
	view.show_state(defeat)
	view._process(maxf(0.0,view.feedback_until-view.elapsed-0.01))
	check(not view.defeat_return_queued,"defeat waits for final attack animation")
	view._process(0.02)
	await process_frame
	view._process(0.1)
	await process_frame
	check(fake.returns==1,"defeat returns automatically exactly once after animations")
	check(not view.hp_bars[0].visible,"knocked-out actor loses overhead HP meter")
	view.world = null
	fake.queue_free()
	view.open_battle(state)
	settle(view)
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
	if DisplayServer.get_name() != "headless":
		view.open_battle(state)
		view._process(0.65)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/mvp-battle-falling-tiles.png")
		view._process(view.TRANSITION_SECONDS+0.45-view.elapsed)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../artifacts/mvp-battle-walk-in.png")
		settle(view)
		var demonstration := state.duplicate(true)
		demonstration.turn = 10
		demonstration.turn_order = ["player"]
		demonstration.enemy_hp = 18
		view.pending_action = "attack"
		view.show_state(demonstration)
		var approach: Dictionary = view.actors[0].motions[0].duplicate()
		var retreat: Dictionary = view.actors[0].motions[1].duplicate()
		var times := [(float(approach.at)+float(approach.end))/2.0,(float(approach.end)+float(retreat.at))/2.0,(float(retreat.at)+float(retreat.end))/2.0,float(retreat.end)+0.02]
		var names := ["approach","strike","return","formation"]
		for i in range(times.size()):
			view._process(maxf(0.0,float(times[i])-view.elapsed))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../artifacts/mvp-battle-%s.png" % names[i])
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)
