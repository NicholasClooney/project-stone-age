extends PanelContainer
## 后台搜宠's info block (AutomationSettings.SHOWCASE_NAME): a few lines at the
## top left, under the Lv/体力/石币 line, newest at the bottom. The server keeps
## the lines (automation status flow.log: found, captured, Lv.120, 留下 / 放生,
## skips, queue drops), so every watching device and a reloaded page show the
## same ones. Local fold/close controls never change automation state.
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const SHOWN := 5
const WIDTH := 560.0
const COLORS := {"found":Color("ffd98a"), "capture":Color("ffd98a"), "paused":Color("f0a08a"), "captured":Color("f8edc7"), "level":Color("f8edc7"), "kept":Color("9fe39a"),
	"released":Color("f0a08a"), "survey":Color("9fd0e3"), "dropped":Color("b6aa8a"), "skipped":Color("b6aa8a"), "retry":Color("b6aa8a"), "resumed":Color("9fe39a")}
var world: Node
var lines: VBoxContainer
var _shown_key := ""
var minimized := false
var dismissed := false
var _active := false
var _has_lines := false
var heading: Label
var fold_button: Button
var close_button: Button
var content: VBoxContainer

func configure(owner: Node) -> void:
	world = owner
	name = "ShowcaseTicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 70
	custom_minimum_size.x = 0
	add_theme_stylebox_override("panel", world.box(Color("141a1d", 0.72), Color("6d5b3d", 0.8)))
	lines = VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 1)
	add_child(lines)
	var header:=HBoxContainer.new()
	header.mouse_filter=Control.MOUSE_FILTER_IGNORE
	lines.add_child(header)
	heading=world.text("抓宠进度",14)
	heading.mouse_filter=Control.MOUSE_FILTER_IGNORE
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	fold_button=world.button("收起",func():
		minimized=not minimized
		_refresh())
	fold_button.name="ShowcaseFold"
	fold_button.custom_minimum_size=Vector2(64,44)
	header.add_child(fold_button)
	close_button=world.button("关闭",func():
		dismissed=true
		_refresh())
	close_button.name="ShowcaseClose"
	close_button.custom_minimum_size=Vector2(64,44)
	close_button.tooltip_text="关闭本次进度；下次抓宠自动显示"
	header.add_child(close_button)
	content=VBoxContainer.new()
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	lines.add_child(content)
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
	var active:=bool(automation.get("hunt",{}).get("running",false)) or str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]
	if active and not _active:
		dismissed=false
		minimized=false
	_active=active
	var shown := shown_lines(automation)
	_has_lines=not shown.is_empty()
	var key := JSON.stringify(shown)
	if key != _shown_key:
		_shown_key = key
		for child in content.get_children():
			content.remove_child(child)
			child.queue_free()
		for line in shown:
			var label: Label = world.text(str(line.get("text", "")), 14)
			label.name = "Line_" + str(line.get("kind", ""))
			label.add_theme_color_override("font_color", COLORS.get(str(line.get("kind", "")), Color("f8edc7")))
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(label)
		reset_size()
	_refresh()

## Under the status line; during a shown battle the field's line is hidden, so
## the block keeps the same spot.
func place() -> void:
	var screen:Vector2=world.get_viewport_rect().size
	custom_minimum_size.x=minf(WIDTH,screen.x-16)
	size.x=custom_minimum_size.x
	var hint:Control=world.adventure_hint
	position=Vector2(8,70)
	if is_instance_valid(hint):position=Vector2(maxf(8,hint.position.x-4),hint.position.y+maxf(hint.size.y,20)+6)
	position.x=minf(position.x,screen.x-size.x-8)

func _refresh()->void:
	content.visible=not minimized
	fold_button.text="展开" if minimized else "收起"
	close_button.visible=not _active
	heading.text="抓宠进度"+(" · 运行中" if _active else " · 已停止")
	reset_size()
	place()
	visible=_has_lines and not dismissed and not _covered()

## Top-left compact form avoids the automation chips at the bottom-right.
## Both forms give way to menus; hiding a viewer never sends a server command.
func _covered() -> bool:
	for key in ["adventure_menu","helper_menu","settings_menu","dialogue","quest_helper_menu","pet_encyclopedia","training_helper","leveling_destinations","changelog_menu","character_selection","dev_gm_menu","dev_map_overview","pet_training","item_storage_menu"]:
		var window=world.get(key)
		if is_instance_valid(window) and window.visible:return true
	return is_instance_valid(world.pet_hunt_menu) and world.pet_hunt_menu.visible and not world.pet_hunt_menu.minimized

func _process(_delta: float) -> void:
	if _has_lines:
		visible=not dismissed and not _covered()
		if visible:place()
