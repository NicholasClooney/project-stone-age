extends RefCounted
## Input for the game scene (scripts/game.gd): key bindings, held movement
## keys, Esc and the other keys for whichever window is open, clicks and the
## wheel on the field. The game keeps its _input and _unhandled_input
## callbacks (so Godot's event order is unchanged) and hands each event here;
## see docs/technical/game-scripts.md.
const Shortcuts = preload("res://scripts/shortcuts.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

## The default keys (scripts/shortcuts.gd); a device's own choice replaces
## them once restore_device_settings runs (load_shortcuts).
func configure_input() -> void:
	game.shortcuts = Shortcuts.defaults()
	Shortcuts.apply(game.shortcuts)

## This device's keys from viewer.cfg (设置 → 快捷键).
func load_shortcuts() -> void:
	game.shortcuts = Shortcuts.merged(game.viewer_pref("shortcuts",{}))
	Shortcuts.apply(game.shortcuts)

## Puts key in the action's slot (0 clears it). A key another action uses is
## refused and that action returned, unless swap: then the other action takes
## this slot's previous key. Returns "" when the binding changed.
func bind_shortcut(action: String, slot: int, key: int, swap: bool = false) -> String:
	if not game.shortcuts.has(action) or slot<0 or slot>=Shortcuts.SLOTS or key==KEY_ESCAPE:return action
	var previous: int = int(game.shortcuts[action][slot])
	var holder := Shortcuts.owner_of(game.shortcuts,key,action)
	if not holder.is_empty():
		if not swap:return holder
		var keys: Array = game.shortcuts[holder]
		keys[keys.find(key)] = previous
	# The same key twice on one action keeps only this slot.
	var own: Array = game.shortcuts[action]
	for i in range(own.size()):
		if i!=slot and key!=0 and int(own[i])==key:own[i] = 0
	own[slot] = key
	_save_shortcuts()
	return ""

func reset_shortcuts() -> void:
	game.shortcuts = Shortcuts.defaults()
	_save_shortcuts()

func _save_shortcuts() -> void:
	Shortcuts.apply(game.shortcuts)
	if game._device_settings_live:game.set_viewer_pref("shortcuts",Shortcuts.overrides(game.shortcuts))

func on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and game.get_viewport().gui_get_focus_owner() is LineEdit:
		game._last_typing_msec = Time.get_ticks_msec()
	# 开发者性能面板 works over every window and battle, and before the game loads.
	if event.is_action_pressed("perf") and not event.is_echo() and not game.get_viewport().gui_get_focus_owner() is LineEdit:
		game.toggle_perf_panel();game.get_viewport().set_input_as_handled();return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(game.pet_workflow) and game.pet_workflow.phase=="restart":
		game.pet_workflow.stop_cycle("已手动停止",not game.pet_workflow.stop_pending().is_empty());game.get_viewport().set_input_as_handled();return
	if game.data.is_empty():
		return
	if game.link_blocked():
		# The login screen's fields still type.
		if game.get_viewport().gui_get_focus_owner() is LineEdit:return
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:game.get_viewport().set_input_as_handled()
		return
	# Typing (一般频道 or any other field) never walks.
	var typing: bool = game.get_viewport().gui_get_focus_owner() is LineEdit
	for action in ["north","south","west","east"]:
		if event.is_action_pressed(action) and not event.is_echo() and not game.paused_input and not typing:
			if is_instance_valid(game.quest_helper_travel):game.quest_helper_travel.cancel()
			if is_instance_valid(game.travel_router):game.travel_router.cancel("手动移动取消了自动寻路。")
			game.pending_talk = false
			game.held.erase(action)
			game.held.append(action)
			game.path.clear()
		elif event.is_action_released(action):
			game.held.erase(action)

func on_unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(game.quest_helper_travel) and (game.quest_helper_travel.active or game.state.derived.get("quest_auto",{}).get("running",false)):
		game.quest_helper_travel.cancel("已停止任务导航或自动任务。")
		game.get_viewport().set_input_as_handled()
		return
	for modal in [game.quest_helper_menu,game.leveling_destinations,game.helper_menu]:
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
	if is_instance_valid(game.pet_encyclopedia) and game.pet_encyclopedia.visible:
		if event.is_action_pressed("encyclopedia"):game.pet_encyclopedia.close_menu()
		game.get_viewport().set_input_as_handled()
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
		elif battle_window_key(event):
			pass
		elif event.is_action_pressed("ui_accept") and not game.battle_session.snapshot().active and not game.battle_window_open():
			game.return_from_battle()
		game.get_viewport().set_input_as_handled()
		return
	if game.dialogue.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
			game.close_dialogue()
		game.get_viewport().set_input_as_handled()
		return
	# Enter opens 一般频道's line on a multi-profile server.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and is_instance_valid(game.chat_panel) and game.chat_panel.available() and not game.settings_menu.visible:
		game.chat_panel.open_input()
		game.get_viewport().set_input_as_handled()
		return
	# M (Ctrl+M too) opens the classic map window.
	if event.is_action_pressed("map") or (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_M):
		game.classic_hud.toggle_map()
		game.get_viewport().set_input_as_handled()
		return
	# Esc closes the top window first: the map, then the radio, then 设置.
	if event.is_action_pressed("ui_cancel") and game.classic_hud.map_panel.visible:
		game.classic_hud.toggle_map()
		return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(game.radio_panel) and game.radio_panel.visible and not game.settings_menu.visible:
		game.radio_panel.close_panel()
		game.get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("mute"):
		game.toggle_mute()
	elif event.is_action_pressed("help"):
		if game.settings_menu.visible and game.settings_menu.page=="help":game.settings_menu.close_menu()
		elif not game.dialogue.visible:game.settings_menu.open_menu("help")
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("settings"):
		# With no window open Esc opens 设置 (the classic 系统 menu).
		if game.settings_menu.visible:game.settings_menu.close_menu()
		elif not game.dialogue.visible:game.settings_menu.open_menu()
	elif event.is_action_pressed("helper"):
		if not game.settings_menu.visible:game.helper_menu.open_menu()
	elif event.is_action_pressed("radio"):
		game.toggle_radio()
	elif event.is_action_pressed("encyclopedia"):
		if not game.settings_menu.visible:game.pet_encyclopedia.open_menu()
	elif event.is_action_pressed("zoom_in") and not game.paused_input:
		game.zoom_by(GameScene.ZOOM_STEP)
	elif event.is_action_pressed("zoom_out") and not game.paused_input:
		game.zoom_by(-GameScene.ZOOM_STEP)
	elif event.is_action_pressed("character"):
		game.change_character()
	elif event.is_action_pressed("sit") and not game.moving:
		game.player.set_action(3 if game.player.action==5 else 5)
	elif event.is_action_pressed("wave") and not game.moving:
		game.player.set_action(6)
	elif event is InputEventMouseButton and event.pressed and not game.paused_input:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_world_click(game.get_global_transform_with_canvas().affine_inverse()*event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			turn_toward(game.get_global_transform_with_canvas().affine_inverse()*event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.zoom_by(GameScene.ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.zoom_by(-GameScene.ZOOM_STEP)

## The window shortcuts a battle allows (设置, 操作说明, 游戏助手, 电台,
## 宠物大全). Esc closes 设置 or the radio, else opens 设置; it only gets
## here when the battle has no command to cancel (battle_view.gd
## nothing_to_cancel). Returns whether the key was used.
func battle_window_key(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		if game.settings_menu.visible:game.settings_menu.close_menu()
		elif is_instance_valid(game.radio_panel) and game.radio_panel.visible:game.radio_panel.close_panel()
		else:game.settings_menu.open_menu()
	elif event.is_action_pressed("settings"):
		if game.settings_menu.visible:game.settings_menu.close_menu()
		else:game.settings_menu.open_menu()
	elif event.is_action_pressed("help"):
		if game.settings_menu.visible and game.settings_menu.page=="help":game.settings_menu.close_menu()
		else:game.settings_menu.open_menu("help")
	elif event.is_action_pressed("helper"):
		if not game.settings_menu.visible:game.helper_menu.open_menu()
	elif event.is_action_pressed("radio"):
		game.toggle_radio()
	elif event.is_action_pressed("encyclopedia"):
		if not game.settings_menu.visible:game.pet_encyclopedia.open_menu()
	else:return false
	return true

func handle_world_click(point: Vector2) -> void:
	if game.paused_input:
		return
	if game.dev_blink_mode:
		game.blink_to(Vector2i(game.unproject(point).round()));return
	if is_instance_valid(game.quest_helper_travel):game.quest_helper_travel.cancel()
	if is_instance_valid(game.travel_router):game.travel_router.cancel("手动点击取消了自动寻路。")
	if is_instance_valid(game.world_travel) and game.world_travel.handle_click(point):return
	if is_instance_valid(game.npc_sprite) and game.npc_sprite.get_rect().has_point(game.npc_sprite.to_local(point)):
		game.approach_npc()
	else:
		var destination := Vector2i(game.unproject(point).round())
		if game.is_walkable(destination):game.walk_to(destination)
		else:game.walk_toward(destination)

## 右键转向 (map.cpp turnAround): a right click turns the standing character
## towards the pointer in one of the 8 directions, without walking; handy for
## facing a player before 加入队伍. On a multi-profile server the others see it.
func turn_toward(point: Vector2) -> void:
	if game.paused_input or game.moving:return
	var d: Vector2 = game.unproject(point)-Vector2(game.cell)
	if d.length()<0.5:return
	var best := -1
	var best_dot := -INF
	for i in range(GameScene.SCREEN_DIRECTIONS.size()):
		var dot := d.normalized().dot(Vector2(GameScene.SCREEN_DIRECTIONS[i]).normalized())
		if dot>best_dot:
			best_dot = dot
			best = i
	var facing := (best+4)%8
	if int(game.player.facing)==facing:return
	game.player.facing = facing
	if is_instance_valid(game.party_panel) and game.party_panel.available():
		game.link.request({"type":"turn","facing":facing})

func release_keyboard_input() -> void:
	# Focus changes release held keys; an intentional click route keeps running.
	game.held.clear()

func clear_input() -> void:
	if is_instance_valid(game.world_travel):game.world_travel.pending = -1
	game.pending_talk = false
	game.held.clear()
	game.path.clear()
