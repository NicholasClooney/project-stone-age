extends Control
## 宠物大全: every pet species, family by family (网格) or ranked by its
## full-grade Lv.120 potential (列表), with a detail page per species: the
## animated battle sprite, template stats, Lv.120 prediction, the player's own
## pets of it and where it lives, each place with 瞬移去抓 (teleport there and
## open 自动抓极品 targeting it). Opened from 游戏助手, the pet window and its
## shortcut (B by default). Data: scripts/pet_encyclopedia.gd.
## See docs/development/pet-encyclopedia.md.
const Encyclopedia = preload("res://scripts/pet_encyclopedia.gd")
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const PetTable = preload("res://scripts/pet_table.gd")
const AnimatedPortrait = preload("res://scripts/animated_portrait.gd")
const TroopArt = preload("res://server/troop_art.gd")
const PANEL_SIZE := Vector2(1200,720)
const PAGE_SIZE := 30
## List columns: key, caption, width. Keys in Encyclopedia.SORT_KEYS sort.
const COLUMNS := [["thumb","",46],["name","名字",126],["family","系",88],["sum","三围合",62],["top01","前0.1%",56],["attack","攻",48],["defence","防",48],["speed","敏",48],["hp","血",56],["rank","成长级",50],["catchable","可抓",40],["where","出现",196],["go","",82]]
## Thumbnails are cut from sheets for at most this long per frame.
const THUMB_BUDGET_USEC := 8000

var world: Node
var book
var panel: PanelContainer
var body: VBoxContainer
var feedback_label: Label
var search: LineEdit
var catchable_box: CheckBox
var grid_button: Button
var list_button: Button
var scroll: ScrollContainer
var portrait: Control
## grid, list or detail; back_view is where 返回 goes from detail.
var view := "grid"
var back_view := "grid"
var current := -1
var sort_key := "sum"
var sort_reverse := false
var list_page := 0
var facing := 1
var feedback := ""
var owned: Dictionary = {}
## Seams for tests: travel(plan) -> bool moves the character (default
## _travel: a verified teleport), open_hunt(plan) opens 自动抓极品 on the
## plan's species (default _open_hunt).
var travel: Callable
var open_hunt: Callable
## The plan of the last 瞬移去抓, until the character stands at its cell.
var pending_hunt: Dictionary = {}
var _pending_deadline := 0
## [TextureRect, sprite, placeholder] for pictures still to show.
var _thumbs: Array = []
var _thumb_retry_msec := 0

func configure(owner: Node) -> void:
	world = owner
	travel = _travel
	open_hunt = _open_hunt

func _ready() -> void:
	name = "PetEncyclopedia"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250
	panel = PanelContainer.new()
	panel.size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel",world.box(Color("1c2628",0.98),Color("b29b65")))
	add_child(panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation",8)
	panel.add_child(frame)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",10)
	frame.add_child(top)
	var title := PetTable.text("宠物大全","title")
	top.add_child(title)
	grid_button = _toggle("网格",func():_switch("grid"),"EncyclopediaGrid")
	top.add_child(grid_button)
	list_button = _toggle("列表",func():_switch("list"),"EncyclopediaList")
	top.add_child(list_button)
	search = LineEdit.new()
	search.name = "EncyclopediaSearch"
	search.placeholder_text = "搜索名字、俗称或系"
	search.custom_minimum_size = Vector2(220,0)
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text):
		list_page = 0
		if view == "detail":view = back_view
		rebuild())
	top.add_child(search)
	catchable_box = CheckBox.new()
	catchable_box.name = "EncyclopediaCatchable"
	catchable_box.text = "只看野外可抓"
	catchable_box.focus_mode = Control.FOCUS_NONE
	PetTable.style_checkbox(catchable_box)
	catchable_box.toggled.connect(func(_on):
		list_page = 0
		rebuild())
	top.add_child(catchable_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close: Button = world.button("关闭 · Esc",close_menu)
	close.name = "EncyclopediaClose"
	top.add_child(close)
	feedback_label = PetTable.text("","meta",PetTable.TEXT)
	feedback_label.name = "EncyclopediaFeedback"
	frame.add_child(feedback_label)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",6)
	frame.add_child(body)
	hide()

func _toggle(caption: String, callback: Callable, control_name: String) -> Button:
	var control: Button = world.button(caption,callback)
	control.name = control_name
	control.custom_minimum_size = Vector2(64,0)
	return control

## The data, built once per game from the shipped files.
func encyclopedia():
	if book == null:book = Encyclopedia.shared(world.encounter_catalog.data,world.world_catalog.maps)
	return book

## Opens on the grid, or on one species' page when template_id is a pet.
func open_menu(template_id: int = -1) -> void:
	# Opens over a battle too (the battle waits); 瞬移去抓 says why it cannot run.
	if world.area_transition_busy:return
	encyclopedia()
	owned = book.owned_counts(world.session.snapshot())
	feedback = ""
	var entry: Dictionary = book.entry_for(template_id) if template_id >= 0 else {}
	if not entry.is_empty():
		if view != "detail":back_view = view
		view = "detail"
		current = int(entry.id)
		facing = 1
	elif view == "detail":
		view = back_view
	if is_instance_valid(world.travel_router):world.travel_router.cancel("已打开宠物大全。")
	world.clear_input()
	world.paused_input = true
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	rebuild()

func close_menu() -> void:
	if not visible:return
	hide()
	_clear_body()
	world.release_input()
	world.clear_input()

func _switch(next: String) -> void:
	view = next
	rebuild()

func show_species(id: int) -> void:
	if view != "detail":back_view = view
	view = "detail"
	current = id
	facing = 1
	rebuild()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if view == "detail":
			view = back_view
			rebuild()
		else:close_menu()
		get_viewport().set_input_as_handled()

func _clear_body() -> void:
	_thumbs.clear()
	portrait = null
	scroll = null
	if not is_instance_valid(body):return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func rebuild() -> void:
	if not is_instance_valid(body) or book == null:return
	var screen: Vector2 = get_viewport_rect().size
	panel.size = Vector2(minf(PANEL_SIZE.x,screen.x-16),minf(PANEL_SIZE.y,screen.y-16))
	panel.position = ((screen-panel.size)/2).max(Vector2(8,8))
	_clear_body()
	for pair in [[grid_button,"grid"],[list_button,"list"]]:
		pair[0].add_theme_stylebox_override("normal",world.box(Color("775b3c"),PetTable.GOLD) if view == pair[1] else world.box(Color("574431"),Color("9d8354")))
		pair[0].add_theme_color_override("font_color",PetTable.GOLD if view == pair[1] else PetTable.TEXT)
	feedback_label.text = feedback
	feedback_label.visible = not feedback.is_empty()
	match view:
		"list":_build_list()
		"detail":_build_detail()
		_:_build_grid()

func _visible_ids() -> Array:
	return book.filtered(search.text,catchable_box.button_pressed)

# ---- 网格 ------------------------------------------------------------------

func _scroll_area() -> VBoxContainer:
	scroll = ScrollContainer.new()
	scroll.name = "EncyclopediaScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",6)
	scroll.add_child(content)
	return content

func _build_grid() -> void:
	var shown := {}
	for id in _visible_ids():shown[id] = true
	var summary := PetTable.text("共 %d 种 · 按原版宠物相簿分系；点一种看资料、预测和出现地点。" % shown.size(),"meta")
	body.add_child(summary)
	var content := _scroll_area()
	for family in book.families:
		var ids: Array = family.species.filter(func(id):return shown.has(id))
		if ids.is_empty():continue
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation",8)
		heading.add_child(PetTable.text(str(family.name),"section"))
		heading.add_child(PetTable.text("%d种" % ids.size(),"meta"))
		content.add_child(heading)
		var flow := HFlowContainer.new()
		flow.name = "Family%d" % int(family.id)
		flow.add_theme_constant_override("h_separation",6)
		flow.add_theme_constant_override("v_separation",6)
		content.add_child(flow)
		for id in ids:flow.add_child(_grid_cell(book.species[id]))
	if shown.is_empty():content.add_child(PetTable.text("没有符合的宠物。","body"))

func _grid_cell(entry: Dictionary) -> Button:
	var cell := Button.new()
	cell.name = "Species%d" % int(entry.id)
	cell.focus_mode = Control.FOCUS_NONE
	cell.custom_minimum_size = Vector2(104,120)
	PetTable.style_button(cell)
	cell.tooltip_text = _tooltip(entry)
	cell.pressed.connect(func():show_species(int(entry.id)))
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation",0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(stack)
	stack.add_child(_thumb(int(entry.sprite),Vector2(104,86)))
	var caption := PetTable.text(str(entry.name),"name")
	caption.add_theme_font_size_override("font_size",13)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.custom_minimum_size = Vector2(100,0)
	stack.add_child(caption)
	var mine: Dictionary = owned.get(int(entry.id),{})
	var count := int(mine.get("carried",0))+int(mine.get("stored",0))
	var note := PetTable.text(("已有%d" % count) if count > 0 else (str(entry.alias) if not str(entry.alias).is_empty() else str(entry.tag)),"meta",PetTable.GOOD if count > 0 else null)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size",11)
	stack.add_child(note)
	return cell

func _tooltip(entry: Dictionary) -> String:
	var lines := ["%s%s%s · %s" % [entry.name," "+str(entry.tag) if not str(entry.tag).is_empty() else "","（%s）" % entry.alias if not str(entry.alias).is_empty() else "",entry.family_name]]
	var potential: Dictionary = entry.get("potential",{})
	if not potential.is_empty():lines.append("满档Lv.1练到120：三围合均值 %.1f，前0.1%% %d" % [float(potential.mean_sum),int(potential.top01)])
	lines.append(Encyclopedia.where_text(entry))
	return "\n".join(lines)

## A picture box: the sprite's still frame once it is made, a placeholder until
## then (or for good when the art is missing).
func _thumb(sprite: int, bounds: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = bounds
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	var placeholder := PetTable.text("无图" if not Thumbs.possible(sprite) else "…","meta")
	placeholder.name = "Placeholder"
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(placeholder)
	var texture := Thumbs.cached(sprite)
	if texture != null:
		picture.texture = texture
		placeholder.hide()
	elif Thumbs.possible(sprite):
		_thumbs.append([picture,sprite,placeholder])
	return holder

## Fills in pictures of boxes on screen, a few per frame; a sprite whose web
## pack is missing is fetched in the background and retried.
func _update_thumbs() -> void:
	if _thumbs.is_empty() or not is_instance_valid(scroll):return
	var area := scroll.get_global_rect()
	var started := Time.get_ticks_usec()
	var retry := Time.get_ticks_msec() >= _thumb_retry_msec
	var waiting: Array = []
	for item in _thumbs.duplicate():
		var picture: TextureRect = item[0]
		if not is_instance_valid(picture):
			_thumbs.erase(item)
			continue
		if not area.intersects(picture.get_global_rect()):continue
		var sprite := int(item[1])
		var texture := Thumbs.cached(sprite)
		if texture == null and Thumbs.possible(sprite):
			if not ResourceLoader.exists(Thumbs.sheet_path(sprite)):
				if retry:waiting.append(sprite)
				continue
			if Time.get_ticks_usec()-started > THUMB_BUDGET_USEC:break
			texture = Thumbs.texture(sprite)
		if texture != null:
			picture.texture = texture
			item[2].hide()
		elif not Thumbs.possible(sprite):
			item[2].text = "无图"
		else:continue
		_thumbs.erase(item)
	if retry:
		_thumb_retry_msec = Time.get_ticks_msec()+800
		if not waiting.is_empty() and world.asset_packs.enabled:world.asset_packs.prefetch(world.asset_packs.sprite_packs(waiting))

func _process(_delta: float) -> void:
	if visible:_update_thumbs()
	if not pending_hunt.is_empty():_check_arrival()

# ---- 列表 ------------------------------------------------------------------

func _build_list() -> void:
	var ids: Array = Encyclopedia.ranked(book.species,_visible_ids(),sort_key,sort_reverse)
	var pages := maxi(1,int(ceil(ids.size()/float(PAGE_SIZE))))
	list_page = clampi(list_page,0,pages-1)
	var note := PetTable.text("按满档（四项+2）Lv.1捕获练到120级的三围合均值排名（攻＋防＋敏，每种100万只模拟，固定种子）。前0.1%：一千只里最好那只的三围合。点列标题换排序。","meta")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	body.add_child(_list_header())
	var content := _scroll_area()
	var start := list_page*PAGE_SIZE
	for i in range(start,mini(ids.size(),start+PAGE_SIZE)):content.add_child(_list_row(book.species[ids[i]],i))
	if ids.is_empty():content.add_child(PetTable.text("没有符合的宠物。","body"))
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation",10)
	body.add_child(pager)
	var previous: Button = world.button("◀ 上一页",func():
		list_page -= 1
		rebuild())
	previous.name = "EncyclopediaPrevious"
	previous.disabled = list_page <= 0
	pager.add_child(previous)
	pager.add_child(PetTable.text("第 %d / %d 页 · %d 种" % [list_page+1,pages,ids.size()],"body"))
	var following: Button = world.button("下一页 ▶",func():
		list_page += 1
		rebuild())
	following.name = "EncyclopediaNext"
	following.disabled = list_page >= pages-1
	pager.add_child(following)

func _list_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "EncyclopediaHeader"
	row.add_theme_constant_override("separation",6)
	var lead := Control.new()
	lead.custom_minimum_size = Vector2(6,0)
	row.add_child(lead)
	for column in COLUMNS:
		var key: String = column[0]
		if not Encyclopedia.SORT_KEYS.has(key):
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(column[2],0)
			row.add_child(gap)
			continue
		var arrow := ""
		if key == sort_key:arrow = " ▲" if sort_reverse != (key == "name" or key == "family") else " ▼"
		var head := Button.new()
		head.name = "Sort_"+key
		head.text = str(column[1])+arrow
		head.flat = true
		head.focus_mode = Control.FOCUS_NONE
		head.custom_minimum_size = Vector2(column[2],0)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT if key in ["name","family","where"] else HORIZONTAL_ALIGNMENT_RIGHT
		head.add_theme_font_override("font",PetTable.font(600))
		head.add_theme_font_size_override("font_size",12)
		head.add_theme_color_override("font_color",PetTable.GOLD if key == sort_key else PetTable.MUTED)
		head.add_theme_color_override("font_hover_color",PetTable.BRIGHT)
		head.tooltip_text = "按%s排序；再点一次反过来。" % Encyclopedia.SORT_KEYS[key]
		head.pressed.connect(func():sort_by(key))
		row.add_child(head)
	return row

## Sorts the list by a column; the same column again reverses it.
func sort_by(key: String) -> void:
	if key == sort_key:sort_reverse = not sort_reverse
	else:
		sort_key = key
		sort_reverse = false
	list_page = 0
	rebuild()

func _list_row(entry: Dictionary, index: int) -> PanelContainer:
	var holder := PetTable.row_panel(index)
	holder.name = "Row%d" % int(entry.id)
	holder.tooltip_text = _tooltip(entry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	holder.add_child(row)
	var potential: Dictionary = entry.get("potential",{})
	for column in COLUMNS:
		var key: String = column[0]
		var width: float = column[2]
		match key:
			"thumb":row.add_child(_thumb(int(entry.sprite),Vector2(width,40)))
			"name":
				var open := Button.new()
				open.name = "Open%d" % int(entry.id)
				open.flat = true
				open.focus_mode = Control.FOCUS_NONE
				open.alignment = HORIZONTAL_ALIGNMENT_LEFT
				open.text = str(entry.name)+(" "+str(entry.tag) if not str(entry.tag).is_empty() else "")
				open.clip_text = true
				open.custom_minimum_size = Vector2(width,0)
				open.add_theme_font_override("font",PetTable.font(600))
				open.add_theme_font_size_override("font_size",14)
				open.add_theme_color_override("font_color",PetTable.BRIGHT)
				open.add_theme_color_override("font_hover_color",PetTable.GOLD)
				open.tooltip_text = "查看资料" if str(entry.alias).is_empty() else "%s · 查看资料" % entry.alias
				open.pressed.connect(func():show_species(int(entry.id)))
				row.add_child(open)
			"family":
				var family := PetTable.text(str(entry.family_name),"meta",PetTable.TEXT)
				family.custom_minimum_size = Vector2(width,0)
				family.clip_text = true
				row.add_child(family)
			"sum":row.add_child(PetTable.cell("%.1f" % float(potential.get("mean_sum",0)) if not potential.is_empty() else "—",width,true))
			"top01":row.add_child(PetTable.cell(int(potential.top01) if not potential.is_empty() else "—",width))
			"attack","defence","speed","hp":
				var value = potential.get("mean_"+key,null)
				row.add_child(PetTable.cell(roundi(float(value)) if value != null else "—",width))
			"rank":row.add_child(PetTable.cell("%d级" % int(entry.rank),width))
			"catchable":row.add_child(PetTable.cell("可" if entry.catchable else "否",width,false,PetTable.GOOD if entry.catchable else PetTable.MUTED))
			"where":
				var where := PetTable.text(Encyclopedia.where_text(entry),"meta",PetTable.TEXT if entry.catchable else PetTable.MUTED)
				where.custom_minimum_size = Vector2(width,0)
				where.clip_text = true
				if int(entry.wild_lowest) > 1:where.add_theme_color_override("font_color",Color("e6c284"))
				row.add_child(where)
			"go":row.add_child(_go_button(entry,Encyclopedia.best_location(entry),"Go%d" % int(entry.id),width))
	return holder

func _go_button(entry: Dictionary, place: Dictionary, control_name: String, width: float = 82) -> Button:
	var go: Button = world.button("瞬移去抓",func():go_catch(place))
	go.name = control_name
	go.custom_minimum_size = Vector2(width,0)
	PetTable.style_button(go,true)
	go.disabled = place.is_empty() or not str(place.get("reason","")).is_empty()
	if place.is_empty():go.tooltip_text = "没有能传送去抓的地点：%s" % Encyclopedia.where_text(entry)
	elif go.disabled:go.tooltip_text = str(place.reason)
	else:go.tooltip_text = "传送到%s (%d, %d)，Lv.%d–%d，并打开自动抓极品选中%s。" % [_place_name(place),int(place.cell[0]),int(place.cell[1]),int(place.level_min),int(place.level_max),entry.name]
	return go

static func _place_name(place: Dictionary) -> String:
	return str(place.map_name) if not str(place.map_name).is_empty() else "未导入地图 #%d" % int(place.map_id)

# ---- 详情 ------------------------------------------------------------------

func _build_detail() -> void:
	var entry: Dictionary = book.species.get(current,{})
	if entry.is_empty():
		view = back_view
		_build_grid()
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",10)
	body.add_child(top)
	var back: Button = world.button("◀ 返回",func():
		view = back_view
		rebuild())
	back.name = "EncyclopediaBack"
	top.add_child(back)
	var heading := PetTable.text(str(entry.name),"title")
	heading.name = "SpeciesName"
	top.add_child(heading)
	if not str(entry.alias).is_empty():top.add_child(PetTable.text(str(entry.alias),"section"))
	var same: Array = entry.ids.filter(func(id):return int(id) != int(entry.id))
	top.add_child(PetTable.text("%s · 原表 #%d%s" % [entry.family_name,int(entry.id),"（同值 #%s）" % "、#".join(same.map(func(id):return str(id))) if not same.is_empty() else ""],"meta"))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	columns.add_child(_detail_art(entry))
	columns.add_child(_detail_stats(entry))
	columns.add_child(_detail_places(entry))

func _column(width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(width,0)
	column.add_theme_constant_override("separation",8)
	return column

func _detail_art(entry: Dictionary) -> VBoxContainer:
	var column := _column(300)
	var stage_card := PetTable.card()
	stage_card.custom_minimum_size = Vector2(300,260)
	column.add_child(stage_card)
	var stage := Control.new()
	stage.name = "SpeciesStage"
	stage.clip_contents = true
	stage.custom_minimum_size = Vector2(288,250)
	stage_card.add_child(stage)
	var sprite := int(entry.sprite)
	var pack: String = world.asset_packs.sprite_pack(sprite) if world.asset_packs.enabled else ""
	if not Thumbs.has_art(sprite):
		stage.add_child(_centered(PetTable.text("暂无原版战斗图\n（该精灵未导入）","body",PetTable.MUTED),stage.custom_minimum_size))
	elif not pack.is_empty() and not world.asset_packs.is_ready([pack]):
		stage.add_child(_centered(PetTable.text("下载战斗图中…","body",PetTable.MUTED),stage.custom_minimum_size))
		var shown := current
		world.asset_packs.ensure([pack],func(ok: bool):
			if visible and view == "detail" and current == shown:
				if not ok:feedback = "战斗图下载失败，请稍后再试。"
				rebuild(),"宠物图")
	else:
		portrait = AnimatedPortrait.new()
		portrait.name = "SpeciesPortrait"
		portrait.position = Vector2(144,200)
		portrait.scale = Vector2(1.5,1.5)
		stage.add_child(portrait)
		portrait.setup(str(sprite),facing,func(turned: int):facing = turned)
	var turn := HBoxContainer.new()
	turn.add_theme_constant_override("separation",8)
	column.add_child(turn)
	for step in [-1,1]:
		var button: Button = world.button("◀ 转向" if step < 0 else "转向 ▶",func():turn_portrait(step))
		button.name = "TurnLeft" if step < 0 else "TurnRight"
		button.disabled = portrait == null
		turn.add_child(button)
	turn.add_child(PetTable.text("也可点图转向","meta"))
	var family: Dictionary = {}
	for group in book.families:
		if int(group.id) == int(entry.family):family = group
	column.add_child(PetTable.text("同系 · %s" % entry.family_name,"section"))
	var flow := HFlowContainer.new()
	flow.name = "SpeciesVariants"
	flow.add_theme_constant_override("h_separation",4)
	flow.add_theme_constant_override("v_separation",4)
	column.add_child(flow)
	for id in family.get("species",[]):
		var member: Dictionary = book.species[id]
		var pick := Button.new()
		pick.name = "Variant%d" % int(id)
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(70,80)
		pick.tooltip_text = _tooltip(member)
		PetTable.style_button(pick,true)
		if int(id) == int(entry.id):pick.add_theme_stylebox_override("normal",PetTable._button_style(Color("3b3a28"),PetTable.GOLD))
		pick.pressed.connect(func():show_species(int(id)))
		var stack := VBoxContainer.new()
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_theme_constant_override("separation",0)
		pick.add_child(stack)
		stack.add_child(_thumb(int(member.sprite),Vector2(70,46)))
		var caption := PetTable.text(str(member.name)+("\n"+str(member.tag) if not str(member.tag).is_empty() else ""),"meta",PetTable.TEXT)
		caption.add_theme_font_size_override("font_size",11)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.clip_text = true
		caption.custom_minimum_size = Vector2(68,0)
		stack.add_child(caption)
		flow.add_child(pick)
	# The variants are small; show their pictures without a scroll area.
	scroll = null
	call_deferred("_fill_variant_thumbs")
	return column

func _fill_variant_thumbs() -> void:
	for item in _thumbs.duplicate():
		if not is_instance_valid(item[0]):continue
		var texture := Thumbs.texture(int(item[1]))
		if texture != null:
			item[0].texture = texture
			item[2].hide()
			_thumbs.erase(item)
		elif not Thumbs.possible(int(item[1])):item[2].text = "无图"

func turn_portrait(step: int) -> void:
	if portrait == null:return
	facing = posmod(facing+step,8)
	portrait.facing = facing
	portrait.current_image = -1
	portrait._update(Time.get_ticks_msec())

static func _centered(label: Label, bounds: Vector2) -> Label:
	label.size = bounds
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _detail_stats(entry: Dictionary) -> VBoxContainer:
	var column := _column(410)
	column.name = "SpeciesStats"
	var card := PetTable.card()
	column.add_child(card)
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation",3)
	card.add_child(facts)
	facts.add_child(PetTable.text("原表资料","section"))
	var low := 450+20*int(entry.rank)
	facts.add_child(_fact("初始系数",str(entry.initial)))
	facts.add_child(_fact("野生成长",("%s（原表按 %d 计算）" % [entry.raw_growth,int(entry.wild_growth)]) if str(entry.raw_growth) != str(entry.wild_growth) else str(entry.wild_growth)))
	facts.add_child(_fact("成长级",Encyclopedia.rank_text(int(entry.rank))+" · 每级倍率 %d–%d%%" % [low,low+50]))
	var weights := GridContainer.new()
	weights.name = "SpeciesWeights"
	weights.columns = 6
	weights.add_theme_constant_override("h_separation",10)
	facts.add_child(weights)
	for caption in ["成长权重"]+Encyclopedia.WEIGHT_NAMES+["合计"]:weights.add_child(PetTable.text(caption,"head"))
	var rows := [["基准",entry.weights],["满档 +2",entry.weights.map(func(value):return int(value)+2)]]
	for row in rows:
		weights.add_child(PetTable.text(row[0],"meta"))
		var total := 0
		for value in row[1]:
			total += int(value)
			weights.add_child(PetTable.cell(value,36))
		weights.add_child(PetTable.cell(total,36,row[0] != "基准"))
	var elements: Array = []
	for i in range(4):
		if int(entry.elements[i]) > 0:elements.append("%s%d" % [Encyclopedia.ELEMENT_NAMES[i],int(entry.elements[i])])
	facts.add_child(_fact("属性"," ".join(elements) if not elements.is_empty() else "无"))
	facts.add_child(_fact("野外捕获",("可以 · 捕获抗性 %d" % int(entry.capture_resistance)) if entry.catchable else ("无野外出现" if entry.locations.is_empty() else "野外出现但不可捕获")))
	column.add_child(_potential_card("满档 Lv.120 预测 · Lv.1 捕获",entry.get("potential",{}),"PotentialLv1"))
	if not entry.get("wild_potential",{}).is_empty():
		column.add_child(_potential_card("满档 Lv.120 预测 · 野生最低 Lv.%d 捕获" % int(entry.wild_potential.level),entry.wild_potential,"PotentialWild"))
	column.add_child(_owned_card(entry))
	return column

func _fact(caption: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	var head := PetTable.text(caption,"head")
	head.custom_minimum_size = Vector2(64,0)
	row.add_child(head)
	var text := PetTable.text(value,"body")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(300,0)
	row.add_child(text)
	return row

func _potential_card(title: String, potential: Dictionary, control_name: String) -> PanelContainer:
	var card := PetTable.card()
	card.name = control_name
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",2)
	card.add_child(stack)
	stack.add_child(PetTable.text(title,"section"))
	if potential.is_empty():
		stack.add_child(PetTable.text("没有预测数据（重新生成 species_potential.json）。","meta"))
		return card
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation",14)
	stack.add_child(line)
	for pair in [["三围合均值","%.1f" % float(potential.mean_sum),true],["前1%",str(int(potential.top1)),false],["前0.1%",str(int(potential.top01)),false],["样本最高",str(int(potential.max)),false]]:
		var item := VBoxContainer.new()
		item.add_theme_constant_override("separation",-2)
		item.add_child(PetTable.text(pair[0],"head"))
		var value := PetTable.text(pair[1],"number",PetTable.GOLD if pair[2] else null)
		value.add_theme_font_size_override("font_size",18 if pair[2] else 15)
		item.add_child(value)
		line.add_child(item)
	stack.add_child(PetTable.text("均值 攻 %.1f · 防 %.1f · 敏 %.1f · 血 %.1f · 攻击前1%% %d" % [float(potential.mean_attack),float(potential.mean_defence),float(potential.mean_speed),float(potential.mean_hp),int(potential.top1_attack)],"body"))
	stack.add_child(PetTable.text("四项+2，Lv.%d捕获后逐级练到120；%s只模拟，固定种子。" % [int(potential.level),_count_text(int(potential.pets))],"meta"))
	return card

static func _count_text(count: int) -> String:
	return "%d万" % (count/10000) if count >= 10000 and count % 10000 == 0 else str(count)

func _owned_card(entry: Dictionary) -> PanelContainer:
	var card := PetTable.card()
	card.name = "SpeciesOwned"
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",2)
	card.add_child(stack)
	stack.add_child(PetTable.text("我的%s" % entry.name,"section"))
	var mine: Dictionary = owned.get(int(entry.id),{})
	var count := int(mine.get("carried",0))+int(mine.get("stored",0))
	if count == 0:
		stack.add_child(PetTable.text("还没有。","body"))
		return card
	var best: Dictionary = book.owned_best(world.session.snapshot(),entry)
	stack.add_child(PetTable.text("共 %d 只（随身 %d · 仓库 %d）" % [count,int(mine.get("carried",0)),int(mine.get("stored",0))],"body"))
	var mean := float(entry.get("potential",{}).get("mean_sum",0.0))
	var compare := "（满档均值 %.1f）" % mean if mean > 0 else ""
	stack.add_child(PetTable.text("最佳120级三围合 %d · %s%s" % [int(best.best_sum),best.best_sum_pet,compare],"body",PetTable.GOLD if mean > 0 and best.best_sum >= mean else null))
	stack.add_child(PetTable.text("最佳120级攻击 %d · %s" % [int(best.best_attack),best.best_attack_pet],"body"))
	return card

func _detail_places(entry: Dictionary) -> VBoxContainer:
	var column := _column(430)
	column.name = "SpeciesPlaces"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(PetTable.text("出现地点","section"))
	var places: Array = entry.get("locations",[])
	if places.is_empty():
		var none := PetTable.text("无野外出现","name")
		none.name = "NoWildSpawn"
		column.add_child(none)
		var note := PetTable.text("普通遇敌表里没有它。可能要靠任务、活动、蛋或更高版本才能得到；开发调试可用 GM 调试发放。","meta")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(400,0)
		column.add_child(note)
		return column
	var note := PetTable.text("原表普通遇敌区；随机遇敌不保证每场出现。瞬移去抓：传送到该区，打开自动抓极品并选中它。","meta")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(400,0)
	column.add_child(note)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(list_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",3)
	list_scroll.add_child(rows)
	for i in range(places.size()):
		var place: Dictionary = places[i]
		var holder := PetTable.row_panel(i)
		holder.name = "Place%d_%d" % [int(place.map_id),int(place.area_id)]
		rows.add_child(holder)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		holder.add_child(row)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation",-2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		words.add_child(PetTable.text(_place_name(place),"name",PetTable.BRIGHT if place.reason.is_empty() else PetTable.MUTED))
		var level := "Lv.%d" % int(place.level_min) if int(place.level_min) == int(place.level_max) else "Lv.%d–%d" % [int(place.level_min),int(place.level_max)]
		var extra := " · 可抓Lv.1" if place.capturable and int(place.level_min) <= 1 else ""
		words.add_child(PetTable.text("%s%s · 区域 %d%s" % [level,extra,int(place.area_id)," · "+str(place.reason) if not place.reason.is_empty() else ""],"meta"))
		row.add_child(_go_button(entry,place,"GoPlace%d_%d" % [int(place.map_id),int(place.area_id)]))
	return column

# ---- 瞬移去抓 ----------------------------------------------------------------

## Why 瞬移去抓 cannot run now, or "".
func catch_blocked() -> String:
	if world.battle_view.visible or world.battle_session.snapshot().active:return "战斗中不能瞬移。"
	if world.area_transition_busy:return "正在切换地图，请稍候。"
	var automation: Dictionary = world.state.automation
	if bool(automation.get("running",false)) or bool(automation.get("hunt",{}).get("running",false)) or str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]:
		return "自动练级或自动抓极品正在运行，先停止再瞬移。"
	return ""

## Teleports to a location and then opens 自动抓极品 on its species.
func go_catch(place: Dictionary) -> bool:
	var plan := Encyclopedia.catch_plan(place)
	var reason := str(plan.get("error",catch_blocked()))
	if not reason.is_empty():
		feedback = reason
		rebuild()
		return false
	close_menu()
	feedback = ""
	if not travel.call(plan):
		var why := feedback if not feedback.is_empty() else "传送失败。"
		open_menu()
		feedback = why
		rebuild()
		return false
	pending_hunt = plan
	_pending_deadline = Time.get_ticks_msec()+60000
	_check_arrival()
	return true

func _check_arrival() -> void:
	if Time.get_ticks_msec() > _pending_deadline:
		pending_hunt = {}
		return
	if world.area_transition_busy or int(world.data.get("map_id",-1)) != int(pending_hunt.map_id) or world.cell != pending_hunt.cell:return
	var plan := pending_hunt
	pending_hunt = {}
	open_hunt.call(plan)

## The real teleport, with the checks 刷怪传送 makes (leveling_destinations.gd).
func _travel(plan: Dictionary) -> bool:
	var area: Dictionary = world.encounter_catalog.area_at(int(plan.map_id),plan.cell)
	if area.is_empty() or int(area.id) != int(plan.area_id):
		feedback = "原表已改变，这个地点不再对应该遇敌区。"
		return false
	if world.travel_landing.safe_destination(int(plan.map_id),plan.cell) != plan.cell:
		feedback = "该落点已不可用。"
		return false
	if is_instance_valid(world.travel_router):world.travel_router.cancel("瞬移去抓。")
	return world.load_area_id(int(plan.map_id),plan.cell)

## 自动抓极品 with the plan's species as the target (and on its 属性条件 page):
## the target and the Lv.1 limit are saved to the character's hunt settings
## first, so the window shows them however it is opened.
func _open_hunt(plan: Dictionary) -> void:
	world.link.request({"type":"set_automation_settings","settings":{"hunt":{"template":int(plan.template_id),"level_one":bool(plan.level_one)}}})
	var menu: Control = world.pet_hunt_menu
	if menu.visible:menu.refresh_candidates()
	else:menu.open_menu()
	if not menu.visible:return
	var picker = menu.get("stat_species")
	if picker is OptionButton:
		var index: int = picker.get_item_index(int(plan.template_id))
		if index >= 0:
			picker.select(index)
			if menu.has_method("load_stat_settings"):menu.load_stat_settings()
