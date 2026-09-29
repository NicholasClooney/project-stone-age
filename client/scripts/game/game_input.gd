extends RefCounted
## Input for the game scene (scripts/game.gd): key bindings, held movement
## keys, Esc and the other keys for whichever window is open, clicks and the
## wheel on the field. The game keeps its _input and _unhandled_input
## callbacks (so Godot's event order is unchanged) and hands each event here;
## see docs/technical/game-scripts.md.
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func configure_input() -> void:
	var bindings := {"north":[KEY_W,KEY_UP],"south":[KEY_S,KEY_DOWN],"west":[KEY_A,KEY_LEFT],"east":[KEY_D,KEY_RIGHT],"mute":[KEY_M],"reset":[KEY_R],"character":[KEY_TAB],"sit":[KEY_X],"wave":[KEY_E],"help":[KEY_H]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			InputMap.action_add_event(action,event)

func on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and game.get_viewport().gui_get_focus_owner() is LineEdit:
		game._last_typing_msec = Time.get_ticks_msec()
	if event.is_action_pressed("ui_cancel") and is_instance_valid(game.pet_workflow) and game.pet_workflow.phase=="restart":
		game.pet_workflow.stop_cycle("已手动停止");game.get_viewport().set_input_as_handled();return
	if game.data.is_empty():
		return
	if game.link_blocked():
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:game.get_viewport().set_input_as_handled()
		return
	for action in ["north","south","west","east"]:
		if event.is_action_pressed(action) and not event.is_echo() and not game.paused_input:
			if is_instance_valid(game.travel_router):game.travel_router.cancel("手动移动取消了自动寻路。")
			game.pending_talk = false
			game.held.erase(action)
			game.held.append(action)
			game.path.clear()
		elif event.is_action_released(action):
			game.held.erase(action)

func on_unhandled_input(event: InputEvent) -> void:
	for modal in [game.leveling_destinations]:
		if is_instance_valid(modal) and modal.visible:
			if event.is_action_pressed("ui_cancel"):modal.close_menu()
			game.get_viewport().set_input_as_handled()
			return
	if is_instance_valid(game.training_helper) and game.training_helper.visible:
		if event.is_action_pressed("ui_cancel"):game.training_helper.close_menu()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.pet_hunt_menu) and game.pet_hunt_menu.visible:
		if event.is_action_pressed("ui_cancel"):game.pet_hunt_menu.close_menu()
		game.get_viewport().set_input_as_handled()
		return
	if game.data.is_empty():
		return
	if is_instance_valid(game.changelog_menu) and game.changelog_menu.visible:
		if event.is_action_pressed("ui_cancel"):game.changelog_menu.close_menu()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.character_selection) and game.character_selection.visible:
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.dev_gm_menu) and game.dev_gm_menu.visible:
		if event.is_action_pressed("ui_cancel"):game.dev_gm_menu.close_menu()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.dev_map_overview) and game.dev_map_overview.visible:
		if event.is_action_pressed("ui_cancel"):game.dev_map_overview.close_map()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.pet_training) and game.pet_training.visible:
		if event.is_action_pressed("ui_cancel"):game.pet_training.close_training()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.world_travel) and game.world_travel.overlay.visible:
		if event.is_action_pressed("ui_cancel"):game.world_travel._close()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.adventure_menu) and game.adventure_menu.visible:
		if event.is_action_pressed("ui_cancel"):game.close_adventure_menu()
		game.get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.battle_view) and game.battle_view.visible:
		if event.is_action_pressed("mute"):
			game.toggle_mute()
		elif event.is_action_pressed("ui_accept") and not game.battle_session.snapshot().active:
			game.return_from_battle()
		game.get_viewport().set_input_as_handled()
		return
	if game.dialogue.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			game.close_dialogue()
		game.get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_M:
		game.classic_hud.toggle_map()
		game.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and game.classic_hud.map_panel.visible:
		game.classic_hud.toggle_map()
		return
	if event.is_action_pressed("mute"):
		game.toggle_mute()
	elif event.is_action_pressed("help"):
		if game.settings_menu.visible and game.settings_menu.page=="help":game.settings_menu.close_menu()
		elif not game.dialogue.visible:game.settings_menu.open_menu("help")
	elif event.is_action_pressed("ui_cancel"):
		game.settings_menu.close_menu()
	elif event.is_action_pressed("reset"):
		game.reset_player()
	elif event.is_action_pressed("character"):
		game.change_character()
	elif event.is_action_pressed("sit") and not game.moving:
		game.player.set_action(3 if game.player.action==5 else 5)
	elif event.is_action_pressed("wave") and not game.moving:
		game.player.set_action(6)
	elif event is InputEventMouseButton and event.pressed and not game.paused_input:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_world_click(game.get_global_transform_with_canvas().affine_inverse()*event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.zoom_by(GameScene.ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.zoom_by(-GameScene.ZOOM_STEP)

func handle_world_click(point: Vector2) -> void:
	if game.paused_input:
		return
	if game.dev_blink_mode:
		game.blink_to(Vector2i(game.unproject(point).round()));return
	if is_instance_valid(game.travel_router):game.travel_router.cancel("手动点击取消了自动寻路。")
	if is_instance_valid(game.world_travel) and game.world_travel.handle_click(point):return
	if is_instance_valid(game.npc_sprite) and game.npc_sprite.get_rect().has_point(game.npc_sprite.to_local(point)):
		game.approach_npc()
	else:
		var destination := Vector2i(game.unproject(point).round())
		if game.is_walkable(destination):game.walk_to(destination)
		else:game.walk_toward(destination)

func release_keyboard_input() -> void:
	# Focus changes release held keys; an intentional click route keeps running.
	game.held.clear()

func clear_input() -> void:
	if is_instance_valid(game.world_travel):game.world_travel.pending = -1
	game.pending_talk = false
	game.held.clear()
	game.path.clear()
