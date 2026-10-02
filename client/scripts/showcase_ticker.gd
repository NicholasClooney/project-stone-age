extends PanelContainer
## 后台搜宠's info block (AutomationSettings.SHOWCASE_NAME): a few lines at the
## top left, under the Lv/体力/石币 line, newest at the bottom. The server keeps
## the lines (automation status flow.log: found, captured, Lv.120, 留下 / 放生,
## skips, queue drops), so every watching device and a reloaded page show the
## same ones. It never takes input and gives way to menus that would cover it.
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const SHOWN := 5
const WIDTH := 560.0
const COLORS := {"found":Color("ffd98a"), "capture":Color("ffd98a"), "paused":Color("f0a08a"), "captured":Color("f8edc7"), "level":Color("f8edc7"), "kept":Color("9fe39a"),
	"released":Color("f0a08a"), "survey":Color("9fd0e3"), "dropped":Color("b6aa8a"), "skipped":Color("b6aa8a"), "retry":Color("b6aa8a"), "resumed":Color("9fe39a")}
var world: Node
var lines: VBoxContainer
var _shown_key := ""

func configure(owner: Node) -> void:
	world = owner
	name = "ShowcaseTicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 70
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", world.box(Color("141a1d", 0.72), Color("6d5b3d", 0.8)))
	lines = VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 1)
	add_child(lines)
	hide()

## The lines to show for an automation status: the run's newest lines while
## 后台搜宠 is on, none otherwise.
static func shown_lines(automation: Dictionary) -> Array:
	var flow: Dictionary = automation.get("flow", {})
	if not bool(flow.get("showcase", false)):return []
	var log: Array = flow.get("log", [])
	var count := int(flow.get("queue_dropped",0))
	var capacity := SHOWN-1 if count>0 else SHOWN
	var result: Array = log.slice(maxi(0, log.size() - capacity))
	if count>0:
		var species: Dictionary = flow.get("queue_dropped_species",{})
		var names: PackedStringArray = []
		for id in species:
			names.append("%s %d" % [str(flow.get("queue_dropped_names",{}).get(id,id)),int(species[id])])
		result.append({"kind":"dropped","text":"排队淘汰 %d 只（%s）" % [count,"、".join(names)]})
	return result

func on_status(automation: Dictionary) -> void:
	var shown := shown_lines(automation)
	var key := JSON.stringify(shown)
	if key != _shown_key:
		_shown_key = key
		for child in lines.get_children():
			lines.remove_child(child)
			child.queue_free()
		var title: Label = world.text("抓宠进度", 12)
		title.add_theme_color_override("font_color", Color("b6aa8a"))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(title)
		for line in shown:
			var label: Label = world.text(str(line.get("text", "")), 14)
			label.name = "Line_" + str(line.get("kind", ""))
			label.add_theme_color_override("font_color", COLORS.get(str(line.get("kind", "")), Color("f8edc7")))
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = WIDTH - 24
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lines.add_child(label)
		reset_size()
	place()
	visible = not shown.is_empty() and not _covered()

## Under the status line; during a shown battle the field's line is hidden, so
## the block keeps the same spot.
func place() -> void:
	var hint: Control = world.adventure_hint
	if is_instance_valid(hint):position = Vector2(hint.position.x - 4, hint.position.y + maxf(hint.size.y, 20.0) + 6)

## Windows that sit over the top left: the block would hide their content.
func _covered() -> bool:
	for window in [world.adventure_menu, world.helper_menu, world.settings_menu, world.dialogue]:
		if is_instance_valid(window) and window.visible:return true
	return is_instance_valid(world.pet_hunt_menu) and world.pet_hunt_menu.visible and not world.pet_hunt_menu.minimized

func _process(_delta: float) -> void:
	if not _shown_key.is_empty() and _shown_key != "[]":
		var covered := _covered()
		if visible == covered:visible = not covered
		if visible:place()
