extends RefCounted
## The automation windows of the game scene (scripts/game.gd): the character's
## automation settings and their batched sending, reopening windows after a
## reload, and whether minimized automation is running. The windows and the
## pending state stay on the game; see docs/technical/game-scripts.md.
const AutomationSettings = preload("res://scripts/automation_settings.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

## After a reload, reopens the window of a hunt or find-pet workflow that kept
## running on the backend. (The auto-battle window reopens itself on status.)
## A window this device had minimized comes back as its progress bar.
func resume_automation_view() -> void:
	var automation: Dictionary = game.state.automation
	if is_instance_valid(game.training_helper) and game.training_helper.running and not game.training_helper.minimized and not (is_instance_valid(game.pet_workflow) and game.pet_workflow.active()) and bool(game.viewer_pref("training_minimized")):
		game.training_helper.minimize()
	var hunting := bool(automation.get("hunt",{}).get("running",false))
	var flow := str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]
	if (hunting or flow) and is_instance_valid(game.pet_hunt_menu) and not game.pet_hunt_menu.visible and not game.pet_hunt_menu.minimized:
		game.pet_hunt_menu.open_menu()
		if hunting:game.pet_hunt_menu.on_status(automation)
		if bool(game.viewer_pref("hunt_minimized")):game.pet_hunt_menu.minimize()

## The player's overrides from the profile; effective values add the defaults.
func automation_overrides() -> Dictionary:
	var overrides = game.state.profile.get("automation_settings",{})
	return overrides if overrides is Dictionary else {}

## Effective training, capture and hunt settings of this character.
func automation_settings() -> Dictionary:
	return AutomationSettings.effective(automation_overrides())

## Effective Lv.120 stat filter for one species.
func stat_filter(template_id: int) -> Dictionary:
	return AutomationSettings.stat_filter(automation_overrides(),template_id)

## A window changed a settings control. Its patch is sent once the player
## pauses (SETTINGS_SEND_MSEC), so spinbox ticks do not each reach the backend.
func mark_settings_dirty(window: Node) -> void:
	if not window in game._settings_dirty:game._settings_dirty.append(window)
	game._settings_dirty_msec = Time.get_ticks_msec()

## Sends every pending window's changes now (on Apply / Start / Close).
func flush_automation_settings() -> void:
	var patch := {}
	var windows := game._settings_dirty.duplicate()
	game._settings_dirty.clear()
	for window in windows:
		if is_instance_valid(window):patch = AutomationSettings.merged(patch,window.settings_patch())
	if not patch.is_empty():game.link.request({"type":"set_automation_settings","settings":patch})

## The profile's automation settings changed (this or another device): open
## windows show the new values, leaving a control being typed in alone.
func _on_automation_settings() -> void:
	var json := JSON.stringify(automation_overrides())
	if json==game._automation_settings_json:return
	game._automation_settings_json = json
	for window in [game.training_helper,game.pet_hunt_menu]:
		if is_instance_valid(window) and window.is_node_ready():window.load_settings()

func _automation_running() -> bool:
	var automation: Dictionary = game.state.automation
	return bool(automation.get("running",false)) or bool(automation.get("hunt",{}).get("running",false)) or str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]

## True while a minimized automation window (自动练级 / 自动抓极品) runs. Its
## progress bar then stands in for the window: nothing is modal, but the
## character stays in place so the stationary run is not cancelled by a stray click.
func automation_minimized() -> bool:
	return (is_instance_valid(game.training_helper) and game.training_helper.minimized) or (is_instance_valid(game.pet_hunt_menu) and game.pet_hunt_menu.minimized)

func set_clone_squad_enabled(enabled:bool)->void:
	game.session.clone_squad_enabled=enabled
	if is_instance_valid(game.clone_button):game.clone_button.set_pressed_no_signal(game.session.clone_squad_enabled)
