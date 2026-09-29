extends RefCounted
## One visual language for the pet tables (宠物仓库, 同种比较, 放生记录):
## a type scale where each role looks different, stats in aligned columns,
## the best value of a column in gold, zebra rows, compact row-end buttons,
## visible checkboxes and clearly disabled buttons.
##
##   title    20 bold, cream          window titles
##   section  15 semi-bold, gold      group headings (随身宠物, 仓库宠物)
##   name     15 semi-bold, bright    pet names
##   meta     12 regular, muted       ids, levels, places, notes, hints
##   head     12 semi-bold, muted     column headers
##   number   14 medium, tabular      stat cells, right-aligned
const TEXT := Color("f3e6c4")
const BRIGHT := Color("fff6dc")
const MUTED := Color("a39883")
const GOLD := Color("f2c14e")
const GOOD := Color("9fd58a")
const BAD := Color("ef8f7c")
const ROW_A := Color("1f2b2c")
const ROW_B := Color("253435")
const CARD := Color("2f3f3c")
const EDGE := Color("b8a47c")

## Stat columns: key, header, width. max_hp/attack/defence/speed/sum read from
## a stats dictionary (sum = attack + defence + speed).
const COLUMNS := [["level","Lv",34],["max_hp","血",50],["attack","攻",40],["defence","防",40],["speed","敏",40],["sum","三围合",54]]
const GRADE_WIDTH := 70

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}

static func font(weight: int, tabular: bool = false) -> FontVariation:
	var key := "%d:%s" % [weight, tabular]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		variation.variation_opentype = {2003265652:float(weight)} # OpenType wght axis.
		if tabular:variation.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"):1}
		_fonts[key] = variation
	return _fonts[key]

static func text(value: String, role: String = "meta", color: Variant = null) -> Label:
	var spec: Array = {"title":[20,700,TEXT], "section":[15,600,GOLD], "name":[15,600,BRIGHT], "meta":[12,400,MUTED], "head":[12,600,MUTED], "number":[14,500,TEXT], "body":[13,500,TEXT]}[role]
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font(int(spec[1]), role == "number"))
	label.add_theme_font_size_override("font_size", int(spec[0]))
	label.add_theme_color_override("font_color", color if color is Color else spec[2])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Breaks text into at most max_lines lines no wider than width, at its own
## separators ( · ，；、), so the result never depends on the platform's line
## breaking (headless builds cannot break CJK text); the last line ends in …
## when it does not fit.
static func fit_lines(value: String, role: String, width: float, max_lines: int) -> String:
	var probe := text("", role)
	var used: Font = probe.get_theme_font("font")
	var size := probe.get_theme_font_size("font_size")
	probe.free()
	var pieces := []
	var start := 0
	for i in range(value.length()):
		if value[i] in ["·", "，", "；", "、", "\n"]:
			pieces.append(value.substr(start, i - start + 1))
			start = i + 1
	pieces.append(value.substr(start))
	var lines := [""]
	for piece in pieces:
		var candidate: String = lines[-1] + piece
		if lines[-1].strip_edges().is_empty() or used.get_string_size(candidate.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			lines[-1] = candidate
		else:
			lines.append(piece)
	lines = lines.map(func(line):return str(line).strip_edges().trim_suffix("\n"))
	if lines.size() > max_lines:
		lines = lines.slice(0, max_lines)
		lines[-1] = str(lines[-1]) + "…"
	return "\n".join(lines)

## A right-aligned number cell of a fixed width; gold when it is the best.
static func cell(value: Variant, width: float, best: bool = false, color: Variant = null) -> Label:
	var label := text(str(value), "number", GOLD if best else color)
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

## The column header row matching stat_cells. lead: the widths before the first
## stat column plus the separators between them (not the one after them).
static func header(lead: float, after: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(lead, 0)
	row.add_child(spacer)
	for column in COLUMNS:
		var label := text(column[1], "head")
		label.custom_minimum_size = Vector2(column[2], 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	var grade := text("先天", "head")
	grade.custom_minimum_size = Vector2(GRADE_WIDTH, 0)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(grade)
	for caption in after:row.add_child(text(caption, "head"))
	return row

static func value_of(stats: Dictionary, key: String) -> int:
	if key == "sum":return int(stats.get("attack", 0)) + int(stats.get("defence", 0)) + int(stats.get("speed", 0))
	return int(stats.get(key, 0))

## The best value of each column over some stats dictionaries.
static func best_values(all_stats: Array) -> Dictionary:
	var best := {}
	for stats in all_stats:
		for column in COLUMNS:
			var key: String = column[0]
			if key == "level":continue
			best[key] = maxi(int(best.get(key, -1)), value_of(stats, key))
	return best

## Stat cells for one pet. under: optional second values (e.g. Lv120 for a
## younger pet), shown small and muted below each cell.
static func stat_cells(row: HBoxContainer, stats: Dictionary, best: Dictionary, under: Dictionary = {}) -> void:
	for column in COLUMNS:
		var key: String = column[0]
		var value := value_of(stats, key)
		var is_best := key != "level" and best.has(key) and value == int(best[key])
		if under.is_empty() or key == "level":
			row.add_child(cell(value, column[2], is_best))
			continue
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", -2)
		stack.add_child(cell(value, column[2], false))
		var projected := cell(value_of(under, key), column[2], best.has(key) and value_of(under, key) == int(best[key]), MUTED)
		projected.add_theme_font_size_override("font_size", 11)
		stack.add_child(projected)
		row.add_child(stack)

## Innate grade as a 满档 badge, or compact offsets like +2 +1 0 −1.
static func grade(quality: Dictionary) -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(GRADE_WIDTH, 0)
	if quality.is_empty():
		box.add_child(text("未知", "meta"))
	elif bool(quality.get("full", false)):
		box.add_child(badge("满档", GOLD))
	else:
		var parts: Array = quality.offsets.map(func(value):return ("+%d" % value) if int(value) > 0 else ("−%d" % absi(int(value)) if int(value) < 0 else "0"))
		var label := text(" ".join(parts), "meta", TEXT)
		label.tooltip_text = "先天档位 总%+d" % int(quality.total)
		box.add_child(label)
	return box

static func badge(caption: String, color: Color) -> PanelContainer:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.18)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	holder.add_theme_stylebox_override("panel", style)
	var label := text(caption, "meta", color)
	label.add_theme_font_override("font", font(600))
	holder.add_child(label)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return holder

## A zebra row container (index decides the shade) holding one HBox.
static func row_panel(index: int, highlight: bool = false) -> PanelContainer:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("3b3a28") if highlight else (ROW_A if index % 2 == 0 else ROW_B)
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	if highlight:
		style.border_color = GOLD
		style.set_border_width_all(1)
	holder.add_theme_stylebox_override("panel", style)
	return holder

## A card with a lighter background for pinned summaries.
static func card() -> PanelContainer:
	var holder := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = Color(EDGE, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	holder.add_theme_stylebox_override("panel", style)
	return holder

static func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style

## Shared button look (also for world.button buttons): readable hover, pressed
## and an obviously disabled state. compact: the smaller row-end size.
static func style_button(button: Button, compact: bool = false) -> void:
	button.add_theme_stylebox_override("normal", _button_style(Color("574431"), Color("9d8354")))
	button.add_theme_stylebox_override("hover", _button_style(Color("775b3c"), Color("e6c284")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("4a3826"), GOLD))
	button.add_theme_stylebox_override("disabled", _button_style(Color("262e2e"), Color("3f4847")))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", BRIGHT)
	button.add_theme_color_override("font_disabled_color", Color("6c7470"))
	button.add_theme_font_override("font", font(600))
	button.add_theme_font_size_override("font_size", 12 if compact else 13)

## Checkbox icons that read on the dark panels: light border, gold when checked.
static func style_checkbox(box: CheckBox) -> void:
	for state in ["unchecked", "checked", "unchecked_disabled", "checked_disabled"]:
		box.add_theme_icon_override(state, _check_icon(state.begins_with("checked"), state.ends_with("disabled")))
	box.add_theme_color_override("font_color", TEXT)
	box.add_theme_color_override("font_hover_color", BRIGHT)
	box.add_theme_color_override("font_pressed_color", TEXT)
	box.add_theme_color_override("font_hover_pressed_color", BRIGHT)
	box.add_theme_font_override("font", font(500))
	box.add_theme_font_size_override("font_size", 13)

static func _check_icon(checked: bool, disabled: bool) -> Texture2D:
	var key := "%s:%s" % [checked, disabled]
	if _icons.has(key):return _icons[key]
	var size := 16
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var edge := Color("6c7470") if disabled else (GOLD if checked else Color("d8ccb0"))
	var fill := Color(GOLD, 0.35 if disabled else 1.0) if checked else Color("141d1e")
	image.fill_rect(Rect2i(1, 1, size - 2, size - 2), edge)
	image.fill_rect(Rect2i(3, 3, size - 6, size - 6), fill)
	if checked:
		var mark := Color("1b2324")
		for point in [[4,8],[5,9],[6,10],[7,11],[8,10],[9,9],[10,8],[11,7],[12,6],[4,7],[5,8],[6,9],[7,10],[8,9],[9,8],[10,7],[11,6],[12,5]]:
			image.set_pixel(point[0], point[1], mark)
	var texture := ImageTexture.create_from_image(image)
	_icons[key] = texture
	return texture
