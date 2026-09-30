extends CanvasLayer
## 开发者性能面板: a compact overlay at the top right with memory, the
## breakdown by owner, performance and network, refreshed twice a second
## (scripts/perf_monitor.gd). A developer convenience, not original UI. It is
## built on first use (F3 by default, or 设置 → 开发者 → 性能面板) and does
## no work while hidden. Its own layer keeps it above battles and windows;
## the mouse passes through everything but its buttons.
## 导出快照 writes every number as JSON: user://perf-snapshots/ on desktop, a
## browser download (and window.stoneAgePerfSnapshot) on the web.
## See docs/technical/perf-panel.md.
const PerfMonitor = preload("res://scripts/perf_monitor.gd")
const INTERVAL := 0.5
const FONT_SIZE := 12

var world: Node
var monitor := PerfMonitor.new()
var snapshot_dir := "user://perf-snapshots/"
var show_breakdown := true
var last_sample: Dictionary = {}
var last_export := ""
var box: PanelContainer
var main_text: Label
var breakdown_text: Label
var status: Label
var _elapsed := 0.0

func configure(owner: Node) -> void:
	world = owner
	name = "PerfPanel"
	layer = 100
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(world.get("ui_root")):root.theme = world.ui_root.theme
	add_child(root)
	box = PanelContainer.new()
	box.name = "PerfBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = world.box(Color(0.07,0.09,0.1,0.78),Color(0.7,0.6,0.4,0.6))
	style.content_margin_left = 8;style.content_margin_right = 8
	style.content_margin_top = 5;style.content_margin_bottom = 5
	box.add_theme_stylebox_override("panel",style)
	root.add_child(box)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation",3)
	box.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation",6)
	column.add_child(header)
	var title := _label("性能面板 · 开发者")
	title.add_theme_color_override("font_color",Color("e6c284"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for spec in [["PerfBreakdown","明细",toggle_breakdown],["PerfExport","导出快照",export_snapshot],["PerfClose","关闭",close_panel]]:
		var button: Button = world.button(spec[1],spec[2])
		button.name = spec[0]
		button.add_theme_font_size_override("font_size",FONT_SIZE)
		for state in ["normal","hover","pressed","hover_pressed"]:
			var small: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
			small.content_margin_left = 6;small.content_margin_right = 6
			small.content_margin_top = 1;small.content_margin_bottom = 1
			button.add_theme_stylebox_override(state,small)
		header.add_child(button)
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation",14)
	column.add_child(body)
	main_text = _label("")
	main_text.name = "PerfMain"
	body.add_child(main_text)
	breakdown_text = _label("")
	breakdown_text.name = "PerfBreakdownText"
	body.add_child(breakdown_text)
	status = _label("")
	status.name = "PerfStatus"
	status.add_theme_color_override("font_color",Color("b6aa8a"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 300
	column.add_child(status)
	status.hide()
	visible = false
	set_process(false)

func _label(value: String) -> Label:
	var label: Label = world.text(value,FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	return label

func toggle() -> void:
	if visible:close_panel()
	else:open_panel()

func open_panel() -> void:
	visible = true
	set_process(true)
	_elapsed = 0.0
	refresh()

func close_panel() -> void:
	visible = false
	set_process(false)

func toggle_breakdown() -> void:
	show_breakdown = not show_breakdown
	breakdown_text.visible = show_breakdown
	_place()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:return
	_elapsed = 0.0
	refresh()

func refresh() -> void:
	last_sample = monitor.sample(world)
	main_text.text = "\n".join(PerfMonitor.lines(last_sample))
	breakdown_text.text = "\n".join(PerfMonitor.breakdown_lines(last_sample))
	breakdown_text.visible = show_breakdown
	_place()
	if OS.has_feature("web"):JavaScriptBridge.eval("window.stoneAgePerf = %s" % JSON.stringify(last_sample),true)

## Every number now, as JSON. Returns where it went (a path, or "download").
func export_snapshot() -> String:
	refresh()
	var data := PerfMonitor.snapshot(last_sample,world.get_viewport().get_visible_rect().size if world.is_inside_tree() else Vector2.ZERO)
	var text := JSON.stringify(data,"  ",false)
	var file_name := PerfMonitor.snapshot_name(int(data.unix_time))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.stoneAgePerfSnapshot = %s" % JSON.stringify(data),true)
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(),file_name,"application/json")
		DisplayServer.clipboard_set(text)
		print("[perf] snapshot ",text)
		last_export = "download"
		_show_status("已下载 %s，并复制到剪贴板（也在 window.stoneAgePerfSnapshot）。" % file_name)
		return last_export
	DirAccess.make_dir_recursive_absolute(snapshot_dir)
	var path := snapshot_dir.path_join(file_name)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		_show_status("快照保存失败：%s" % error_string(FileAccess.get_open_error()))
		return ""
	file.store_string(text)
	file.close()
	last_export = path
	_show_status("已保存 %s" % ProjectSettings.globalize_path(path))
	print("[perf] snapshot saved to ",ProjectSettings.globalize_path(path))
	return path

## Top right, keeping the right edge in place as the text grows or shrinks.
func _place() -> void:
	box.reset_size()
	box.position = Vector2(maxf(6.0,box.get_parent_area_size().x-box.size.x-6),6)

func _show_status(value: String) -> void:
	status.text = value
	status.show()
	_place()
