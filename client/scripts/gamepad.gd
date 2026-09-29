extends Node
## Game controller support on top of the original mouse-driven UI.
##
## World: left stick / D-pad walk, A talks to whoever is near, B cancels,
## X status, Y pets, LB/RB zoom, Start 设置, Back switches to HUD buttons.
## Menus, battles and dialogue: stick / D-pad move a visible highlight between
## the clickable controls of the top panel, A clicks it (a real mouse click at
## its centre, so every existing control works unchanged), B cancels, LB/RB
## turn pages. Nothing depends on hovering.
const DEADZONE := 0.55
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.12
const PAGE_BACK := ["上一页","◀","<","«"]
const PAGE_NEXT := ["下一页","▶",">","»"]

var world: Node
var target: Control
var hud_mode := false
var _layer: CanvasLayer
var _frame: Panel
var _direction := Vector2i.ZERO
var _repeat := 0.0
var _stick := Vector2.ZERO

func configure(owner: Node) -> void:
	world = owner

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 150
	add_child(_layer)
	_frame = Panel.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1,0.92,0.25,0.12)
	style.border_color = Color(1,0.9,0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	_frame.add_theme_stylebox_override("panel",style)
	_frame.hide()
	_layer.add_child(_frame)
	bind_movement()

## Walking uses the game's own north/south/east/west actions.
static func bind_movement() -> void:
	var bindings := {"north":[JOY_BUTTON_DPAD_UP,JOY_AXIS_LEFT_Y,-1.0],"south":[JOY_BUTTON_DPAD_DOWN,JOY_AXIS_LEFT_Y,1.0],"west":[JOY_BUTTON_DPAD_LEFT,JOY_AXIS_LEFT_X,-1.0],"east":[JOY_BUTTON_DPAD_RIGHT,JOY_AXIS_LEFT_X,1.0]}
	for action in bindings:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var button := InputEventJoypadButton.new()
		button.button_index = bindings[action][0]
		var motion := InputEventJoypadMotion.new()
		motion.axis = bindings[action][1]
		motion.axis_value = bindings[action][2]
		for event in [button,motion]:
			if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)
		InputMap.action_set_deadzone(action,DEADZONE)
	# A and B also confirm and cancel wherever Enter and Escape already do.
	for pair in [["ui_accept",JOY_BUTTON_A],["ui_cancel",JOY_BUTTON_B]]:
		var event := InputEventJoypadButton.new()
		event.button_index = pair[1]
		if InputMap.has_action(pair[0]) and not InputMap.action_has_event(pair[0],event):InputMap.action_add_event(pair[0],event)

## The panel whose controls the highlight moves between, or null in the world.
func panel() -> Control:
	if world.has_method("link_blocked") and world.link_blocked():return world.link_overlay
	for node in [world.leveling_destinations,world.training_helper,world.pet_hunt_menu,world.changelog_menu,world.character_selection,world.dev_gm_menu,world.dev_map_overview,world.pet_training,world.get("helper_menu")]:
		if is_instance_valid(node) and node.visible:return node
	if is_instance_valid(world.world_travel) and world.world_travel.overlay.visible:return world.world_travel.overlay
	# Windows opened over a battle take the controller before the battle.
	var over_battle: Array = [world.get("pet_encyclopedia"),world.help,world.get("radio_panel")] if is_instance_valid(world.battle_view) and world.battle_view.visible else []
	for node in [world.adventure_menu]+over_battle+[world.battle_view,world.dialogue,world.help]:
		if is_instance_valid(node) and node.visible:return node
	if hud_mode and is_instance_valid(world.ui_layer):return world.ui_layer.get_child(0)
	return null

func candidates(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	var viewport_rect := Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size)
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CanvasItem and not node.is_visible_in_tree():continue
		# In HUD mode, skip modal panels that happen to live under the HUD root.
		if hud_mode and node!=root and node in [world.adventure_menu,world.battle_view,world.dialogue,world.help,world.training_helper,world.pet_hunt_menu,world.get("helper_menu")]:continue
		if node is BaseButton and not node.disabled and node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:
			var rect := _screen_rect(node)
			if rect.size.x>2 and rect.size.y>2 and viewport_rect.intersects(rect):found.append(node)
		pending.append_array(node.get_children())
	return found

func _screen_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	return transform*Rect2(Vector2.ZERO,control.size)

func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):return
	var root := panel()
	if event is InputEventJoypadMotion:
		if root==null:return
		if event.axis==JOY_AXIS_LEFT_X:_stick.x = event.axis_value
		elif event.axis==JOY_AXIS_LEFT_Y:_stick.y = event.axis_value
		else:return
		var direction := Vector2i(int(signf(_stick.x)) if absf(_stick.x)>DEADZONE else 0,int(signf(_stick.y)) if absf(_stick.y)>DEADZONE else 0)
		if direction!=_direction:
			_direction = direction
			if direction!=Vector2i.ZERO:
				move(Vector2(direction));_repeat = REPEAT_DELAY
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		if event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT] and root!=null:
			_direction = Vector2i.ZERO
			get_viewport().set_input_as_handled()
		return
	match event.button_index:
		JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT:
			if root==null:return
			var direction: Vector2i = {JOY_BUTTON_DPAD_UP:Vector2i.UP,JOY_BUTTON_DPAD_DOWN:Vector2i.DOWN,JOY_BUTTON_DPAD_LEFT:Vector2i.LEFT,JOY_BUTTON_DPAD_RIGHT:Vector2i.RIGHT}[event.button_index]
			_direction = direction
			move(Vector2(direction));_repeat = REPEAT_DELAY
			get_viewport().set_input_as_handled()
		JOY_BUTTON_A:
			if root!=null and is_instance_valid(target) and target.is_visible_in_tree():
				click(target);get_viewport().set_input_as_handled()
			elif root==null:
				interact();get_viewport().set_input_as_handled()
		JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER:
			var forward: bool = event.button_index==JOY_BUTTON_RIGHT_SHOULDER
			if root!=null:page(root,forward)
			else:world.zoom_by(world.ZOOM_STEP if forward else -world.ZOOM_STEP)
			get_viewport().set_input_as_handled()
		JOY_BUTTON_X:
			if root==null or root==world.adventure_menu:world.show_adventure_menu("status");get_viewport().set_input_as_handled()
		JOY_BUTTON_Y:
			if root==null or root==world.adventure_menu or root==world.battle_view:world.show_adventure_menu("pets");get_viewport().set_input_as_handled()
		JOY_BUTTON_START:
			if root==null or root==world.help or root==world.battle_view:
				if world.settings_menu.visible:world.settings_menu.close_menu()
				else:world.settings_menu.open_menu()
				get_viewport().set_input_as_handled()
		JOY_BUTTON_BACK:
			if root!=null and not hud_mode:return
			hud_mode = not hud_mode
			if hud_mode:world.clear_input()
			target = null
			get_viewport().set_input_as_handled()
		JOY_BUTTON_B:
			if hud_mode and root!=null and root==world.ui_layer.get_child(0):
				hud_mode = false;target = null;get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var root := panel()
	if root==null:
		_frame.hide()
		target = null
		return
	var options := candidates(root)
	if not is_instance_valid(target) or not target in options:
		target = _replacement(root,options)
	if is_instance_valid(target):
		_spot_root = root
		_spot = _screen_rect(target)
	if _direction!=Vector2i.ZERO:
		_repeat -= delta
		if _repeat<=0:
			move(Vector2(_direction));_repeat = REPEAT_RATE
	if not is_instance_valid(target) or not _used_recently():
		_frame.hide();return
	var rect := _screen_rect(target).grow(3)
	_frame.position = rect.position
	_frame.size = rect.size
	_frame.show()

## The highlight appears once a controller is in use, so mouse play looks unchanged.
var _last_pad_msec := -100000
func _used_recently() -> bool:
	return Time.get_ticks_msec()-_last_pad_msec < 30000 or Input.get_connected_joypads().size()>0

func _initial(options: Array[Control]) -> Control:
	if options.is_empty():return null
	var best: Control = options[0]
	for option in options:
		var a := _screen_rect(option).position
		var b := _screen_rect(best).position
		if a.y<b.y-4 or (absf(a.y-b.y)<=4 and a.x<b.x):best = option
	return best

## A panel redrawn with new data replaces its controls; the highlight stays on
## whatever now sits where it was, instead of jumping back to the first control.
var _spot_root: Control
var _spot := Rect2()
func _replacement(root: Control, options: Array[Control]) -> Control:
	if root==_spot_root:
		for option in options:
			if _screen_rect(option).get_center().distance_to(_spot.get_center())<=6:return option
	return _initial(options)

## Moves the highlight to the nearest control in a screen direction.
func move(direction: Vector2) -> void:
	_last_pad_msec = Time.get_ticks_msec()
	var root := panel()
	if root==null:return
	var options := candidates(root)
	if not is_instance_valid(target) or not target in options:
		target = _replacement(root,options);return
	var origin := _screen_rect(target).get_center()
	var best: Control
	var best_score := INF
	for option in options:
		if option==target:continue
		var offset := _screen_rect(option).get_center()-origin
		var along := offset.dot(direction)
		if along<=4:continue
		var across := absf(offset.dot(Vector2(-direction.y,direction.x)))
		var score := along+across*2.5
		if score<best_score:best_score = score;best = option
	if best!=null:target = best

## A real left click at the control's centre, as the mouse would produce.
func click(control: Control) -> void:
	_last_pad_msec = Time.get_ticks_msec()
	var point: Vector2 = get_viewport().get_final_transform()*_screen_rect(control).get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = point
		button.global_position = point
		Input.parse_input_event(button)

func page(root: Control, forward: bool) -> void:
	var labels: Array = PAGE_NEXT if forward else PAGE_BACK
	for option in candidates(root):
		var caption := str(option.get("text")) if option.get("text")!=null else ""
		if caption in labels or option.tooltip_text in labels:
			click(option);return

## A in the world: talk to the villager or resident in reach, else approach the nearest one.
func interact() -> void:
	_last_pad_msec = Time.get_ticks_msec()
	if world.paused_input or world.moving:return
	if not world.npc_data.is_empty() and world.in_talk_range(world.cell):
		world.open_dialogue();return
	var nearest := -1
	var distance := 99
	if is_instance_valid(world.world_travel):
		for i in range(world.world_travel.entries.size()):
			var entry: Dictionary = world.world_travel.entries[i]
			if entry.get("role","")=="decoration":continue
			var gap: Vector2i = (Vector2i(entry.cell[0],entry.cell[1])-world.cell).abs()
			if maxi(gap.x,gap.y)<distance:distance = maxi(gap.x,gap.y);nearest = i
	var npc_gap: int = 99 if world.npc_data.is_empty() else maxi(absi(world.npc_cell.x-world.cell.x),absi(world.npc_cell.y-world.cell.y))
	if npc_gap<=distance and npc_gap<=8:world.approach_npc()
	elif nearest>=0 and distance<=8:world.world_travel.approach(nearest)
	else:world.message.text = "附近没有可以交谈的人。"
