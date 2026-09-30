extends RefCounted
## The game's keyboard shortcuts: which actions exist, their default keys and
## how a device's own choice (viewer.cfg "shortcuts", set on 设置 → 快捷键)
## becomes Godot's InputMap. Each action has up to SLOTS keys; 0 is an empty
## slot. Only keyboard events are rebuilt, so the gamepad's bindings
## (scripts/gamepad.gd) stay. Esc is fixed: it closes the top window and,
## with none open, opens 设置 (see game_input.gd); it cannot be bound.

const SLOTS := 2
## [action, caption, default keys]. Order is the order on the 快捷键 page.
const ACTIONS := [
	["north","向上走",[KEY_W,KEY_UP]],
	["south","向下走",[KEY_S,KEY_DOWN]],
	["west","向左走",[KEY_A,KEY_LEFT]],
	["east","向右走",[KEY_D,KEY_RIGHT]],
	["zoom_in","放大",[KEY_EQUAL,KEY_KP_ADD]],
	["zoom_out","缩小",[KEY_MINUS,KEY_KP_SUBTRACT]],
	["map","地图",[KEY_M]],
	["helper","游戏助手",[KEY_G]],
	["encyclopedia","宠物大全",[KEY_B]],
	["settings","设置（Esc 固定可用）",[]],
	["help","操作说明",[KEY_H]],
	["radio","电台",[]],
	["mute","音乐开关",[]],
	["character","换角色",[KEY_TAB]],
	["sit","坐下 / 站起",[KEY_X]],
	["wave","挥手",[KEY_E]],
	["perf","性能面板（开发者）",[KEY_F3]],
]

static func caption(action: String) -> String:
	for entry in ACTIONS:
		if entry[0]==action:return entry[1]
	return action

static func defaults() -> Dictionary:
	var result := {}
	for entry in ACTIONS:result[entry[0]] = _slots(entry[2])
	return result

static func _slots(keys: Array) -> Array:
	var result: Array = []
	for i in range(SLOTS):result.append(int(keys[i]) if i<keys.size() else 0)
	return result

## Defaults with a device's saved choices laid over them; unknown actions,
## malformed values and Esc are dropped.
static func merged(saved: Variant) -> Dictionary:
	var result := defaults()
	if not saved is Dictionary:return result
	for action in saved:
		if not result.has(action) or not saved[action] is Array:continue
		var keys: Array = []
		for value in saved[action]:
			var code := int(value) if (value is int or value is float) else 0
			keys.append(0 if code==KEY_ESCAPE or code<0 else code)
		result[action] = _slots(keys)
	return result

## Only the actions that differ from the defaults, as saved in viewer.cfg.
static func overrides(bindings: Dictionary) -> Dictionary:
	var base := defaults()
	var result := {}
	for action in bindings:
		if base.has(action) and bindings[action]!=base[action]:result[action] = bindings[action].duplicate()
	return result

## The action already using key, other than skip, or "".
static func owner_of(bindings: Dictionary, key: int, skip: String = "") -> String:
	if key==0:return ""
	for action in bindings:
		if action!=skip and bindings[action].has(key):return action
	return ""

## Replaces every action's keyboard events with bindings (gamepad events stay).
static func apply(bindings: Dictionary) -> void:
	for action in bindings:
		if not InputMap.has_action(action):InputMap.add_action(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:InputMap.action_erase_event(action,event)
		for code in bindings[action]:
			if int(code)==0:continue
			var event := InputEventKey.new()
			event.physical_keycode = int(code)
			InputMap.action_add_event(action,event)

static func key_name(code: int) -> String:
	if code==0:return "（无）"
	return OS.get_keycode_string(code)
