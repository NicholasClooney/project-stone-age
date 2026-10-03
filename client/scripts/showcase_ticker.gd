extends Panel
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
var minimized := true
var dismissed := false
var _active := false
var _has_lines := false
var _showcase := false
var _measure_key := ""
var heading: Label
var summary: Label
var fold_button: Button
var close_button: Button
var content: VBoxContainer
var scroll: ScrollContainer
var actions: HBoxContainer
var stop_button: Button
const MAX_CONTENT_HEIGHT := 180.0

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
	heading.mouse_filter=Control.MOUSE_FILTER_PASS
	heading.clip_text=true
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	fold_button=world.button("收起",func():
		minimized=true
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
	summary=world.text("",12)
	summary.name="ShowcaseLiveSummary"
	summary.clip_text=true
	summary.mouse_filter=Control.MOUSE_FILTER_PASS
	add_child(summary)
	content=VBoxContainer.new()
	content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	scroll=ScrollContainer.new()
	scroll.name="ShowcaseLogScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	actions=HBoxContainer.new()
	add_child(actions)
	for entry in [["设置",_open_settings],["记录",_open_records],["停止",_stop]]:
		var action:Button=world.button(entry[0],entry[1])
		action.custom_minimum_size=Vector2(64,36)
		actions.add_child(action)
	stop_button=actions.get_child(2)
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
	_showcase=bool(automation.get("flow",{}).get("showcase",false))
	var active:=bool(automation.get("hunt",{}).get("running",false)) or str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]
	if active and not _active:
		dismissed=false
		minimized=true
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
	_refresh()

## Under the status line; during a shown battle the field's line is hidden, so
## the block keeps the same spot.
func place() -> void:
	var screen:Vector2=world.get_viewport_rect().size
	var width:=minf(WIDTH,screen.x-16)
	var hint:Control=world.adventure_hint
	position=Vector2(8,70)
	if is_instance_valid(hint):position=Vector2(maxf(8,hint.position.x-4),hint.position.y+maxf(hint.size.y,20)+6)
	position.x=minf(position.x,screen.x-width-8)
	# Panel (not Container) owns its bounds. Fresh wrapped labels initially
	# report thousands of pixels at width zero; that minimum must never resize
	# the outer viewer. Lay out the scrolling viewport before measuring labels.
	lines.position=Vector2(10,6)
	lines.size=Vector2(width-20,44)
	summary.position=Vector2(10,54)
	summary.size=Vector2(width-20,64)
	scroll.position=Vector2(10,118)
	scroll.size.x=width-20
	var available:=minf(MAX_CONTENT_HEIGHT,screen.y-position.y-294)
	for sibling in get_parent().get_children():
		if sibling is Control and str(sibling.name).ends_with("Chip") and sibling.visible:
			available=minf(available,sibling.position.y-position.y-170)
	available=maxf(30,available)
	var measure_key:=str(width)+":"+str(available)+":"+_shown_key
	if measure_key==_measure_key:return
	_measure_key=measure_key
	var text_width:=width-20-scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var height:=0.0
	for label in content.get_children():
		# Use the same font, wrap mode and width as the Label. Reserving the
		# scrollbar width prevents scrollbar visibility from feeding back into
		# line wrapping and alternating the panel height.
		label.custom_minimum_size.x=text_width
		label.size.x=text_width
		var font:Font=label.get_theme_font("font")
		var font_size:int=label.get_theme_font_size("font_size")
		height+=font.get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,text_width,font_size,-1,TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE).y+content.get_theme_constant("separation")
	scroll.size=Vector2(width-20,minf(available,maxf(1,height)))
	actions.position=Vector2(10,scroll.position.y+scroll.size.y+4)
	actions.size=Vector2(width-20,36)
	size=Vector2(width,actions.position.y+42)

func expand() -> void:
	dismissed=false
	minimized=false
	_refresh()

func has_progress() -> bool:
	return (_has_lines or (_showcase and _active)) and not dismissed

func _open_settings() -> void:
	if world.pet_hunt_menu.minimized:world.pet_hunt_menu.restore()
	else:world.pet_hunt_menu.open_menu()

func _open_records() -> void:
	world.adventure_menu.open_pet_records("caught",-1)

func _stop() -> void:
	world.pet_hunt_menu.stop_all("已停止筛选。")

func _refresh()->void:
	content.visible=true
	fold_button.text="收起"
	close_button.visible=not _active
	stop_button.visible=_active
	stop_button.text="立即停止" if not str(world.state.automation.get("flow",{}).get("stop_pending","")).is_empty() else "停止"
	heading.text="抓宠进度"+(" · 运行中" if _active else " · 已停止")
	place()
	visible=has_progress() and not minimized and not _covered()
	_sync_chip()

func _sync_chip() -> void:
	if not _showcase:return
	var menu=world.pet_hunt_menu
	if not is_instance_valid(menu):return
	if has_progress():
		menu._chip()
		if _active:
			menu._update_chip()
			heading.text=menu.chip.title.text.replace("自动抓极品 · 找宠流程","抓宠进度")
			heading.tooltip_text=heading.text
			summary.text=menu.chip.detail.text
			summary.tooltip_text=summary.text
	if has_progress() and minimized and not _covered():
		menu._chip().pop_up()
		if not _active:menu.chip.present("抓宠进度 · 已停止","展开查看本次记录")
	elif is_instance_valid(menu.chip):menu.chip.hide()

## The top-left detail avoids the other automation chips at the bottom-right.
## Both forms give way to menus; hiding a viewer never sends a server command.
func _covered() -> bool:
	for key in ["adventure_menu","helper_menu","settings_menu","dialogue","quest_helper_menu","pet_encyclopedia","training_helper","leveling_destinations","changelog_menu","character_selection","dev_gm_menu","dev_map_overview","pet_training","item_storage_menu"]:
		var window=world.get(key)
		if is_instance_valid(window) and window.visible:return true
	return is_instance_valid(world.pet_hunt_menu) and world.pet_hunt_menu.visible and not world.pet_hunt_menu.minimized

func _process(_delta: float) -> void:
	if _has_lines or (_showcase and _active):
		visible=has_progress() and not minimized and not _covered()
		if visible:place()
		_sync_chip()
