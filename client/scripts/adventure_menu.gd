extends Control
## Original resource frames with a narrow, functional single-player menu set.
var world: Node
var kind := "status"
var panel: Control
var feedback := ""
var allocation_amount := 1
var allocation_stats: Array = ["vitality","strength","toughness","dexterity"]
var selected_pet := 0
var pet_view := "list"
var pet_rename := false
var pet_category := "全部"
var pet_page := 0
var pet_growth_open := false
var pet_compare_open := false
var pet_compare_subject:Dictionary={}
var pet_compare_id := ""
var pet_storage_open := false
var pet_storage_target_id := ""
var pet_compare_page := 0
var pet_storage_page := 0
## The view and page the panel was last built for; scroll is kept within one.
var _built_view: Array = []
var _records_drawn: Array = []
var records_draw_count := 0
var _records_sync_pending := false
var _storage_sync_pending := false
## 同种比较 order (PetComparison.SORT_KEYS, first key first) and whether
## favourites lead each group; this device's choice (viewer.cfg), loaded on first use.
var pet_compare_order: Array = []
var pet_compare_favorites_first := true
var pet_compare_carried_first := true
var _compare_prefs_loaded := false
var pet_compare_projected := false
# 放生 selection for the comparison overlay: stable pet_id -> true, per species.
var pet_release_selected: Dictionary = {}
var pet_release_species := ""
var pet_release_confirm := false
var pet_release_metric := 0
var pet_release_below := 620
## 保留规则 preview: pet_id -> reasons it stays (empty: released), shown on rows.
var pet_rule_reasons: Dictionary = {}
var feedback_tooltip := ""
const RELEASE_METRICS := ["stat_total","attack","defence","speed"]
const PetComparison=preload("res://scripts/pet_comparison.gd")
const KeepRule=preload("res://scripts/keep_rule.gd")
const PetTable=preload("res://scripts/pet_table.gd")
const ReleaseLog=preload("res://server/release_log.gd")
## 宠物记录 view: open, tab (caught / released / stops / queue), filters
## (template id, -1 all; run "latest" or "" for all), page, the last page the
## backend sent and whether one is on its way.
var pet_records_open := false
var records_tab := "caught"
var records_template := -1
var records_run := "latest"
var records_page := 0
var records_data: Dictionary = {}
var records_loading := false
## Stat sort per sortable tab ({released, queue} -> [key, ascending]; key ""
## is the tab's own order: newest first, or the queue's rank) and 只看未捕获
## in 放生; with the tab, this device's (viewer.cfg records_*).
var records_sorts := {"released":["",false],"queue":["",false]}
var records_uncaught := false
var _records_prefs_loaded := false
## 宠物仓库 order (PetComparison.storage_rows: "", caught_new, caught_old) and
## 收藏优先, this device's (viewer.cfg), loaded with the comparison prefs.
var storage_order := ""
var storage_favorites_first := true
var storage_ascending := false
var storage_species := ""
const PetStatFilter=preload("res://scripts/pet_stat_filter.gd")
const PetGrowth = preload("res://scripts/pet_growth.gd")
const AnimatedPortrait = preload("res://scripts/animated_portrait.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const Riding = preload("res://scripts/riding.gd")
const Elements = preload("res://server/elements.gd")
const ElementBars = preload("res://scripts/element_bars.gd")
## 属性 editor on the status window: open, and the draft in creation points
## (0..10 per element, login.cpp's nowSelCharAttr).
var element_editor_open := false
var element_draft: Array = []
const Faces = preload("res://scripts/faces.gd")
## The 精灵 equipment's data (itemset.txt / magic.txt rows, read only).
const OriginalEquipment = preload("res://server/original_equipment.gd")
const Spirits = preload("res://server/spirits.gd")
const GameSessionScript = preload("res://server/game_session.gd")
## The bag's slots in order (menu.cpp:8976: five a row, 51 px apart, rows 48 px).
const BAG := ["potion","club","mirror_charm","healing_charm","haru_armor","freya_robe","teo_robe","koyala_charm"]
## The item shop's stock: the original Samgir shop's potion and club, then
## conveniences (docs/reverse-engineering/magic-and-mp.md says where the
## original sells each piece of spirit equipment).
const SHOP := ["potion","club","mirror_charm","haru_armor","freya_robe","teo_robe","koyala_charm"]
## Facing of the pet window's portrait; the original starts at 1 each time it opens.
var pet_portrait_facing := 1
var name_edit: LineEdit
var art: Dictionary = {}
var quest_catalog = preload("res://scripts/quest_catalog.gd").new()
var selected_original_item := -1
var original_use_pet_id := ""
var original_item_busy := false
var selected_item := "potion"
var selected_item_slot := "potion"
const Highlight = preload("res://scripts/legacy_ui_highlight.gd")
var readable_font: FontVariation
func _sync_dev_visibility() -> void:
	if world==null or not is_instance_valid(world.ui_layer):return
	if is_instance_valid(world.adventure_hint):world.adventure_hint.visible=not visible
	for root_control in world.ui_layer.get_children():
		for child in root_control.get_children():
			if child is HFlowContainer:child.visible=not visible

func configure(owner: Node) -> void:
	world = owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(layout_panel)
	z_index = 50
	visibility_changed.connect(_sync_dev_visibility)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()
func _has_point(point: Vector2) -> bool:
	# Leave the original bottom menu reachable while blocking world/dev clicks.
	return point.y < size.y-40

func open_menu(next_kind: String) -> void:
	kind = next_kind
	pet_view = "list"
	# 宠物记录 opens on purpose only (open_pet_records sets it after this).
	pet_records_open = false
	pet_rename = false
	element_editor_open = false
	pet_portrait_facing = 1
	feedback = ""
	selected_pet = maxi(0,int(world.session.snapshot().active_pet))
	show()
	rebuild()
func refresh(note: String = "") -> void:
	feedback = note
	call_deferred("rebuild")
func original(ident: int) -> Texture2D:
	if art.has(ident):return art[ident]
	for folder in ["res://assets/legacy/mvp/ui/","res://assets/legacy/ui/"]:
		var path: String = folder+str(ident)+".png"
		if ResourceLoader.exists(path):
			art[ident] = load(path)
			return art[ident]
	return null
func image(ident: int, point: Vector2) -> void:
	var texture := original(ident)
	if texture==null:return
	var view := TextureRect.new()
	view.texture = texture
	view.position = point
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)
func stone(rect: Rect2) -> void:
	var cols := int(rect.size.x/64)
	var rows := int(rect.size.y/48)
	for y in range(rows):
		for x in range(cols):
			var row := 0 if y==0 else (2 if y==rows-1 else 1)
			var col := 0 if x==0 else (2 if x==cols-1 else 1)
			image(26001+row*3+col,rect.position+Vector2(x*64,y*48))
func label(value: String, point: Vector2, width: float = 280, font_size: int = 16) -> Label:
	var item: Label = world.text(value,font_size)
	if readable_font==null:
		readable_font=FontVariation.new()
		readable_font.base_font=load("res://assets/fonts/NotoSansSC.ttf")
		readable_font.variation_opentype={2003265652:600.0}
	item.add_theme_font_override("font",readable_font)
	item.position = point
	item.size.x = width
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_color_override("font_color",Color.WHITE)
	item.add_theme_color_override("font_shadow_color",Color.BLACK)
	item.add_theme_constant_override("shadow_offset_x",1)
	item.add_theme_constant_override("shadow_offset_y",1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.z_index=1
	panel.add_child(item)
	return item
func choice(caption: String, point: Vector2, action: String, value: Variant = null, enabled: bool = true) -> Button:
	var item := Button.new()
	item.text = caption
	item.position = point
	item.size = Vector2(238,30)
	item.disabled = not enabled
	item.focus_mode = Control.FOCUS_NONE
	item.add_theme_font_size_override("font_size",16)
	# Transparent interaction rows over the original stone window.
	for style in ["normal","hover","pressed","disabled"]:
		item.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	item.add_theme_color_override("font_color",Color("ffe890"))
	item.add_theme_color_override("font_hover_color",Color.WHITE)
	item.add_theme_color_override("font_pressed_color",Color("d0c060"))
	item.pressed.connect(func(): world.perform_adventure_action(action,value))
	panel.add_child(item)
	return item
## Every rebuild (a sort, a checkbox, backend data) keeps the lists where the
## player left them, as long as the same view and page stay on screen.
func rebuild() -> void:
	if world==null or not visible:return
	var view := [kind,pet_view,pet_category,pet_page,pet_compare_open,pet_compare_page,pet_storage_open,pet_storage_page,pet_records_open,records_tab,records_page,records_template,records_run,storage_order,storage_favorites_first,storage_ascending,storage_species,records_sorts.get(records_tab,[]),records_uncaught]
	if kind=="pets" and pet_records_open and is_instance_valid(panel) and panel.find_child("PetRecordsPanel",false,false)!=null:
		_refresh_records_panel(view)
		return
	if kind=="pets" and pet_storage_open and not pet_compare_open and is_instance_valid(panel) and panel.find_child("PetStoragePanel",false,false)!=null:
		_refresh_storage_panel(view)
		return
	var before: Array[Vector2i] = world.capture_scroll(self) if view==_built_view else ([] as Array[Vector2i])
	_rebuild_panel()
	_built_view = view.duplicate(true)
	_records_drawn = [records_data.duplicate(true),records_loading] if pet_records_open else []
	world.restore_scroll(self,before)

## Reuse the warehouse controls on state pushes, just as records do.
func _refresh_storage_panel(view:Array)->void:
	var select:=panel.find_child("StorageSpecies",true,false) as OptionButton
	if select!=null and select.get_popup().visible:
		if not _storage_sync_pending:
			_storage_sync_pending=true
			get_tree().create_timer(0.1).timeout.connect(func():
				_storage_sync_pending=false
				rebuild())
		return
	var live:=panel
	panel=Control.new()
	pet_storage_panel(world.session.snapshot())
	var draft:=panel
	panel=live
	_sync_records_controls(live.get_child(0),draft.get_child(0))
	if view!=_built_view:
		(live.find_child("StorageScroll",true,false) as ScrollContainer).scroll_vertical=0
	draft.free()
	_built_view=view.duplicate(true)

## State pushes do not replace an open records window. Build a detached
## description only when its data/view changes, then reconcile reusable controls.
func _refresh_records_panel(view:Array)->void:
	var drawn:=[records_data,records_loading]
	if view==_built_view and drawn==_records_drawn:return
	# Keep an open species/run popup usable until the player finishes choosing.
	for control_name in ["RecordsSpecies","RecordsRun"]:
		var select:=panel.find_child(control_name,true,false) as OptionButton
		if select!=null and select.get_popup().visible:
			if not _records_sync_pending:
				_records_sync_pending=true
				get_tree().create_timer(0.1).timeout.connect(func():
					_records_sync_pending=false
					rebuild())
			return
	var live:=panel
	panel=Control.new()
	pet_records_panel()
	var draft:=panel
	panel=live
	_sync_records_controls(live.get_child(0),draft.get_child(0))
	draft.free()
	_built_view=view.duplicate(true)
	_records_drawn=drawn.duplicate(true)
	records_draw_count+=1

func _sync_records_controls(live:Control,draft:Control)->void:
	live.tooltip_text=draft.tooltip_text
	live.custom_minimum_size=draft.custom_minimum_size
	live.size_flags_horizontal=draft.size_flags_horizontal
	live.size_flags_vertical=draft.size_flags_vertical
	live.mouse_filter=draft.mouse_filter
	if not live.get_parent() is Container:
		live.position=draft.position
		live.size=draft.size
	if live is Label:
		live.horizontal_alignment=draft.horizontal_alignment
		live.autowrap_mode=draft.autowrap_mode
		live.clip_text=draft.clip_text
	if live is Label or live is Button:live.text=draft.text
	if live is BaseButton:
		live.disabled=draft.disabled
		if live.toggle_mode:live.set_pressed_no_signal(draft.button_pressed)
		# Refresh callbacks (page count/species choices) without losing hover/focus.
		for signal_name in ["pressed","toggled","item_selected"]:
			if not live.has_signal(signal_name):continue
			for connection in live.get_signal_connection_list(signal_name):live.disconnect(signal_name,connection.callable)
			for connection in draft.get_signal_connection_list(signal_name):live.connect(signal_name,connection.callable)
	if live is OptionButton:
		var same:bool=live.item_count==draft.item_count
		if same:
			for i in range(live.item_count):
				if live.get_item_text(i)!=draft.get_item_text(i):same=false;break
		if not same:
			live.clear()
			for i in range(draft.item_count):live.add_item(draft.get_item_text(i))
		live.select(draft.selected)
	# Exact local overrides: absent values must inherit again, not retain the
	# previous tab/row's colors or styles. Never flatten inherited theme values.
	var overrides:Dictionary={}
	for property in draft.get_property_list():
		var property_name:=str(property.name)
		if property_name.begins_with("theme_override_"):
			var value=draft.get(property_name)
			if value!=null:overrides[property_name]=value
	const OVERRIDE_TYPES:={"colors":"color","constants":"constant","fonts":"font","font_sizes":"font_size","icons":"icon","styles":"stylebox"}
	for property in live.get_property_list():
		var property_name:=str(property.name)
		if not property_name.begins_with("theme_override_") or overrides.has(property_name):continue
		if live.get(property_name)==null:continue
		var category:=property_name.get_slice("/",0).trim_prefix("theme_override_")
		if OVERRIDE_TYPES.has(category):live.call("remove_theme_"+str(OVERRIDE_TYPES[category])+"_override",property_name.get_slice("/",1))
	for property_name in overrides:live.set(property_name,overrides[property_name])
	# Preserve the actual ScrollContainer and its scrollbar throughout updates.
	var scroll_y:int=live.scroll_vertical if live is ScrollContainer else 0
	var children:=draft.get_children()
	for i in range(children.size()):
		var next:Control=children[i]
		if str(next.name).begins_with("StorageRow_"):
			var same:=live.get_node_or_null(NodePath(str(next.name)))
			if same!=null:live.move_child(same,i)
			else:
				draft.remove_child(next);live.add_child(next);live.move_child(next,i)
				continue
		if i<live.get_child_count() and live.get_child(i).get_class()==next.get_class():
			var existing:Control=live.get_child(i)
			existing.name=next.name
			_sync_records_controls(existing,next)
		else:
			if i<live.get_child_count():
				var obsolete:=live.get_child(i);live.remove_child(obsolete);obsolete.queue_free()
			draft.remove_child(next);live.add_child(next);live.move_child(next,i)
	while live.get_child_count()>children.size():
		var obsolete:=live.get_child(live.get_child_count()-1);live.remove_child(obsolete);obsolete.queue_free()
	if live is ScrollContainer:
		live.scroll_vertical=scroll_y

func _notification(what: int) -> void:
	# Reopening the menu starts at the top.
	if what==NOTIFICATION_VISIBILITY_CHANGED and not visible:_built_view = []

func _rebuild_panel() -> void:
	if is_instance_valid(panel):
		remove_child(panel)
		panel.queue_free()
	panel = Control.new()
	var dimensions := {"status":Vector2(272,360),"inventory":Vector2(272,440),"pets":Vector2(272,320),"shop":Vector2(432,468)}
	panel.size = dimensions.get(kind,Vector2(704,432))
	layout_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var profile: Dictionary = world.session.snapshot()
	var p: Dictionary = profile.player
	if kind=="quest":
		stone(Rect2(0,0,704,432))
		label("村外的伙伴",Vector2(24,16),600,21)
	match kind:
		"status":
			status_panel(profile)
		"inventory":
			inventory_panel(profile)
		"pets":
			if pet_records_open:pet_records_panel()
			elif pet_compare_open and not pet_compare_subject.is_empty():pet_comparison_panel(profile,pet_compare_subject)
			elif pet_storage_open:pet_storage_panel(profile)
			else:pet_panel(profile)
		"shop":
			shop_panel(profile)
		"quest":
			var q: Dictionary = profile.quest
			var story := "村外的伙伴\n\n到村外战胜三个对手，结识一只宠物，\n再和它一起挑战强壮的乌力斯坦。\n准备好了就回来告诉我。"
			if q.claimed:story = "做得好！你和伙伴已经能独当一面了。\n\n村外还有更多伙伴等着你认识。"
			label(story,Vector2(30,68),355,18)
			label("胜利 %d / 3\n伙伴 %d / 1\n强敌：%s" % [mini(3,int(q.wins)),mini(1,profile.pets.size()),"已战胜" if q.boss_defeated else "未战胜"],Vector2(410,72),260,18)
			choice("接受委托",Vector2(420,205),"accept_quest",null,not q.accepted and not q.claimed)
			choice("领取报酬",Vector2(420,249),"claim_quest",null,q.accepted and q.boss_defeated and not q.claimed)
			choice("休息 / 恢复体力",Vector2(420,305),"heal")
	if kind in ["status","inventory","pets"]:
		return
	var close := TextureButton.new()
	close.texture_normal = original(26042)
	close.texture_hover = close.texture_normal
	# Keep the full original 80px artwork inside the frame.
	close.position = Vector2(panel.size.x-close.texture_normal.get_width()-16,panel.size.y-38)
	label(feedback,Vector2(8,panel.size.y-42),close.position.x-16,13)
	close.tooltip_text = "关闭 · Esc"
	close.pressed.connect(world.close_adventure_menu)
	panel.add_child(close)

func layout_panel() -> void:
	if not is_instance_valid(panel):return
	# menu.cpp MakeWindowDisp: left windows (4,4), inventory (365,4)
	# in 640px; higher resolutions add their extra width to right windows.
	if kind == "inventory":
		panel.position = Vector2(maxf(4,size.x-275),4)
	elif kind in ["status","pets"]:
		panel.position = Vector2(4,4)
	else:
		panel.position = (size-panel.size)/2

func item_icon(item: String, point: Vector2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = load("res://assets/legacy/mvp/images/%s.png" % ("mirror_charm" if item=="healing_charm" else item))
	view.position = point
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)
	return view

func art_button(ident: int, point: Vector2, action: String, value: Variant = null, enabled: bool = true) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = original(ident)
	button.texture_hover = button.texture_normal
	button.position = point
	button.disabled = not enabled
	button.modulate.a = 1.0 if enabled else 0.4
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): world.perform_adventure_action(action,value))
	panel.add_child(button)
	Highlight.attach(button,Rect2(Vector2(-2,-2),button.texture_normal.get_size()+Vector2(4,4)))
	return button

func portrait(sprite: int, point: Vector2, bounds: Vector2) -> void:
	var art: Dictionary = preload("res://scripts/battle_art.gd").art(sprite)
	var animation: Dictionary = AnimatedPortrait.animation_for(str(sprite),3,0)
	var view := TextureRect.new()
	view.texture = SpriteArt.texture(art,SpriteArt.image(animation,0)) if SpriteArt.frame_count(animation) > 0 else null
	PaletteSheet.apply(view,view.texture)
	view.position = point
	view.size = bounds
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)

func status_panel(profile: Dictionary) -> void:
	var p: Dictionary = profile.player
	var effective: Dictionary = world.session.effective_player_stats()
	image(26073,Vector2.ZERO)
	label("旅行者",Vector2(22,43),140,14)
	# menu.cpp:11754 StockDispBuffer(x+209, y+118, pc.faceGraNo): the
	# original face, centred by its ADRN offset. Without imported faces the
	# battle portrait stands in.
	var character := str(profile.get("character_id","100000"))
	var face_texture := Faces.texture(character,int(profile.get("face",0)))
	if face_texture!=null:
		var face_view := TextureRect.new()
		face_view.name = "StatusFace"
		face_view.texture = face_texture
		face_view.position = Vector2(209,118)+Faces.offset(character,int(profile.get("face",0)))
		face_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(face_view)
	else:
		portrait(int(character),Vector2(177,84),Vector2(64,68))
	# menu.cpp:11680: the ninth row is 魅力 (pc.charm).
	# menu.cpp:11676: the fifth row is 气力 (pc.mp).
	var values := [str(p.level),str(p.xp),str(int(p.level)*30-int(p.xp)),"%d / %d" % [p.hp,p.max_hp],"%d / %d" % [int(p.get("mp",Spirits.MAX_MP)),Spirits.MAX_MP],str(effective.attack),str(effective.defence),str(effective.speed),str(int(effective.get("charm",p.get("charm",60))))]
	for i in range(values.size()):label(values[i],Vector2(87,70+i*21),83,13)
	var base_positions := [Vector2(81,288),Vector2(201,288),Vector2(81,308),Vector2(201,308)]
	var base_keys := ["vitality","strength","toughness","dexterity"]
	for i in range(base_keys.size()):label(str(int(int(p.base_stats[base_keys[i]])/100)),base_positions[i],28,13)
	label("石币 %d" % p.gold,Vector2(18,331),248,13)
	var elements: Array = Elements.of(p) if p.has("elements") else Elements.PLAYER_DEFAULT
	ElementBars.add(panel,elements,Vector2(178,179),20)
	# The whole bar column opens the 属性 editor (character creation is deferred).
	var element_button := Button.new()
	element_button.name = "PlayerElements"
	element_button.position = Vector2(176,176)
	element_button.size = Vector2(86,76)
	element_button.focus_mode = Control.FOCUS_NONE
	for style in ["normal","hover","pressed","focus"]:element_button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	element_button.tooltip_text = "属性：%s（点击调整）" % Elements.text(elements)
	element_button.pressed.connect(func():
		element_editor_open = not element_editor_open
		element_draft = elements.map(func(v):return int(v)/10)
		rebuild())
	panel.add_child(element_button)
	if element_editor_open:element_editor(elements,48 if int(p.get("stat_points",0))<=0 else 296)
	# Classic menu.cpp11801-11808: center(136,180) plus original
	# ADRN offsets: LEVEL UP POINT(-71,88), UP(-26,109).
	if int(p.get("stat_points",0))>0:
		image(26075,Vector2(65,268))
		label(str(p.stat_points),Vector2(186,268),40,13)
	var stats := ["vitality","strength","toughness","dexterity"]
	var rows := [Vector2(110,289),Vector2(230,289),Vector2(110,309),Vector2(230,309)]
	var hints := ["体力：体力 +4，攻击及防御各 +0.1","腕力：体力 +1，攻击 +1，防御 +0.1","耐力：体力 +1，防御 +1，攻击 +0.1","速度：体力 +1，敏捷 +1，攻击及防御各 +0.05"]
	for i in range(stats.size()):
		var plus := art_button(26076,rows[i],"allocate_stat",stats[i],int(p.get("stat_points",0))>0)
		plus.texture_pressed = original(26077)
		plus.tooltip_text = hints[i] + "（消耗 1 点；小数累积后取整）"
		plus.name = "Allocate_"+stats[i]
		plus.visible = int(p.get("stat_points",0))>0

	if int(p.get("stat_points",0))>0:
		stone(Rect2(280,48,256,240))
		label("便捷加点",Vector2(294,60),220,17)
		label("UP 每次分配",Vector2(294,94),115,13)
		var count:=SpinBox.new()
		count.name="AllocationAmount"
		count.min_value=1;count.max_value=1000000000;count.step=1
		count.value=allocation_amount
		count.position=Vector2(408,90);count.size=Vector2(115,28)
		count.value_changed.connect(func(value):allocation_amount=int(value))
		panel.add_child(count)
		for i in range(stats.size()):
			var toggle:=CheckBox.new()
			toggle.name="Distribute_"+stats[i]
			toggle.text=["体力","腕力","耐力","速度"][i]
			toggle.position=Vector2(290+(i%2)*115,128+int(i/2)*32)
			toggle.button_pressed=stats[i] in allocation_stats
			var key: String=stats[i]
			toggle.toggled.connect(func(on):
				if on and key not in allocation_stats:allocation_stats.append(key)
				elif not on:allocation_stats.erase(key))
			panel.add_child(toggle)
		var distribute:=choice("剩余点均分到勾选项",Vector2(289,201),"distribute_stats")
		distribute.name="DistributeStats"
		label("只分配剩余点；余数按体腕耐速分配。",Vector2(294,244),225,12)

## The creation screen's 属性 choice: 10 points over at most two neighbouring
## elements, with the original buttons' rules (Elements.creation_step).
func element_editor(current: Array, top: float) -> void:
	if element_draft.size()!=4:element_draft = current.map(func(v):return int(v)/10)
	stone(Rect2(280,top,256,192))
	label("属性",Vector2(294,top+10),220,17)
	var left := 10
	for value in element_draft:left -= int(value)
	label("剩余 %d 点 · 相克：地→水→火→风→地" % left,Vector2(294,top+36),230,12)
	for i in range(4):
		var y := top+62+i*26
		label("%s属性" % Elements.NAMES[i],Vector2(298,y),60,14).add_theme_color_override("font_color",ElementBars.COLORS[i])
		label(str(int(element_draft[i])*10),Vector2(360,y),40,14)
		for plus in [false,true]:
			var step := Button.new()
			step.name = "Element%s%d" % ["Plus" if plus else "Minus",i]
			step.text = "+" if plus else "−"
			step.position = Vector2(410 if not plus else 450,y-2)
			step.size = Vector2(32,24)
			step.focus_mode = Control.FOCUS_NONE
			var index := i
			step.pressed.connect(func():
				element_draft = Elements.creation_step(element_draft,index,plus)
				rebuild())
			panel.add_child(step)
	var chosen: Array = element_draft.map(func(v):return int(v)*10)
	var confirm: Button = world.button("确定",func():
		if world.session.set_player_elements(chosen):
			element_editor_open = false
			refresh("属性已改为 %s。" % Elements.text(chosen))
		else:refresh("属性需分配满 10 点，且最多两种相邻属性。"))
	confirm.name = "ElementConfirm"
	confirm.position = Vector2(300,top+170-16)
	confirm.disabled = not Elements.valid_player(chosen) or chosen==current
	panel.add_child(confirm)
	var cancel: Button = world.button("取消",func():
		element_editor_open = false
		rebuild())
	cancel.name = "ElementCancel"
	cancel.position = Vector2(420,top+170-16)
	panel.add_child(cancel)

func item_name(key: String) -> String:
	if key in Spirits.SPIRIT_ITEMS:return str(Spirits.ITEMS[key].name)
	return {"potion":"耐久力回复药","club":"小棍棒","healing_charm":"恢复护符（辅助）","mirror_charm":"美丽尼亚护身符1"}.get(key,key)

func item_description(key: String) -> String:
	if key in Spirits.SPIRIT_ITEMS:
		var data: Dictionary = Spirits.ITEMS[key]
		var magic: Dictionary = Spirits.magic_of(key)
		return "%s · %s，气力 %d%s%s" % [str(data.memo),str(magic.comment),int(data.mp),"；Lv%d 可装备" % int(data.level) if int(data.level)>0 else "","；只在战斗中" if int(magic.field)==Spirits.FIELD_BATTLE else "；战斗内外都可用"]
	return {"potion":"恢复体力；战斗中也可使用。","club":"攻击 +4；装备后生效。","healing_charm":"恢复存活随身宠；自动战斗半血治疗，不耗气。","mirror_charm":"主动镜之精灵：消耗行动和 5 点气力。"}.get(key,"")

func item_equipped(profile: Dictionary, key: String) -> bool:
	if key in Spirits.SPIRIT_ITEMS:return key in profile.get("equipment",{}).values()
	return bool(profile.get("equipped",false)) if key=="club" else bool(profile.get("equipped_mirror",false)) if key=="mirror_charm" else false

func equip_action(key: String) -> String:
	if key in Spirits.SPIRIT_ITEMS:return "equip_"+key
	return "heal_pets" if key=="healing_charm" else "equip_mirror" if key=="mirror_charm" else "equip"

## Where a worn item shows (menu.cpp:8940 ItemBuffer: 1 BODY (134,129),
## 2 ARM (61,129), 3 DECORATION (32,68)).
func equip_center(key: String) -> Vector2:
	if key=="club":return Vector2(61,129)
	if key in Spirits.ITEMS and str(Spirits.ITEMS[key].slot)=="body":return Vector2(134,129)
	return Vector2(32,68)

func inventory_panel(profile: Dictionary) -> void:
	image(26060,Vector2.ZERO)
	image(26061,Vector2(0,159))
	label(str(profile.player.gold),Vector2(182,84),75,14)
	# Classic five-slot frame: InitItem menu.cpp8940-8973. Weapon is
	# CHAR_ARM=2 at(61,129), not the top-left accessory slot. The frame
	# already contains head/body/hand silhouettes; no invented mannequin.
	for key in ["club","mirror_charm"]+Spirits.SPIRIT_ITEMS:
		if not item_equipped(profile,key):continue
		var center:=equip_center(key)
		var icon:=item_icon(key,Vector2.ZERO)
		if icon.texture==null:continue
		icon.position=Vector2(49,118) if key=="club" else center-icon.texture.get_size()/2
		icon.name="EquippedClubIcon" if key=="club" else "EquippedMirrorIcon" if key=="mirror_charm" else "EquippedIcon_"+key
		var equipped_slot := choice("",center-Vector2(23,23),"",null)
		for connection in equipped_slot.pressed.get_connections():equipped_slot.pressed.disconnect(connection.callable)
		equipped_slot.name="EquippedClub" if key=="club" else "EquippedMirror" if key=="mirror_charm" else "Equipped_"+key
		equipped_slot.size=Vector2(48,48)
		equipped_slot.tooltip_text=item_name(key)+" · 双击卸下"
		var selection: String="equipped" if key=="club" else "equipped_mirror" if key=="mirror_charm" else "equipped_"+key
		Highlight.attach(equipped_slot,Rect2(Vector2(-1,-1),Vector2(50,47)),selected_item_slot==selection)
		equipped_slot.pressed.connect(func(): selected_original_item=-1;selected_item=key;selected_item_slot=selection;rebuild())
		equipped_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				world.perform_adventure_action(equip_action(key),false)
		)
	var bag: Array=[]
	for key in BAG:
		if int(profile.inventory.get(key,0))-(1 if item_equipped(profile,key) else 0)>0:bag.append(key)
	for i in range(bag.size()):
		var key: String = bag[i]
		var cell := Vector2((i%5)*51,int(i/5)*48)
		# Authority inventory is total owned; equipment consumes one visible
		# bag copy without deleting ownership. Spare copies remain in the bag.
		var bag_count := maxi(0,int(profile.inventory.get(key,0))-(1 if item_equipped(profile,key) else 0))
		if bag_count>0:
			var icon := item_icon(key,Vector2.ZERO)
			icon.name="BagIcon_"+key
			# The original centres each item on its slot (32+j, 200+k).
			icon.position = Vector2(32,200)+cell-(icon.texture.get_size()/2 if icon.texture!=null else Vector2.ZERO)
			label(str(bag_count),Vector2(31,201)+cell,40,12).name="BagCount_"+key
		var slot := choice("",Vector2(11,175)+cell,"",null,bag_count>0)
		for connection in slot.pressed.get_connections():slot.pressed.disconnect(connection.callable)
		slot.name="ItemSlot_"+key
		slot.size=Vector2(48,48)
		slot.tooltip_text=item_name(key)+( "" if key=="potion" else " · 双击装备")
		Highlight.attach(slot,Rect2(Vector2(-3,1),Vector2(50,47)),selected_original_item<0 and selected_item_slot==key and bag_count>0)
		slot.pressed.connect(func(): selected_original_item=-1;selected_item=key;selected_item_slot=key;rebuild())
		slot.gui_input.connect(func(event: InputEvent):
			if key!="potion" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				if not item_equipped(world.session.snapshot(),key):world.perform_adventure_action(equip_action(key),true)
		)
	var originals: Array=profile.get("original_items",[])
	var instances: Array=profile.get("original_instances",[])
	var visible_originals:=0
	for index in range(originals.size()):
		var ident:=int(originals[index])
		var entry: Dictionary=instances[index] if index<instances.size() else {}
		var equipped:=OriginalEquipment.worn(profile,int(entry.get("uid",0)))
		var position_index:=bag.size()+visible_originals
		if not equipped:visible_originals+=1
		var cell:=Vector2((position_index%5)*51,int(position_index/5)*48)
		var data: Dictionary=quest_catalog.items.get(str(ident),{})
		var icon:=TextureRect.new()
		var icon_path: String="res://assets/legacy/"+str(data.get("icon_path",""))
		if ResourceLoader.exists(icon_path):icon.texture=load(icon_path)
		icon.name="OriginalItemIcon_%d" % index
		var center:=Vector2(136,59) if ident==2418 else Vector2(61,129) if int(ident) in [2465,2485] else Vector2(32,68) if ident==2427 else Vector2(83,68)
		icon.position=(center if equipped else Vector2(32,200)+cell)-(icon.texture.get_size()/2 if icon.texture!=null else Vector2.ZERO)
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		var slot:=choice("",center-Vector2(23,23) if equipped else Vector2(11,175)+cell,"",null)
		for connection in slot.pressed.get_connections():slot.pressed.disconnect(connection.callable)
		slot.name="OriginalItemSlot_%d" % index;slot.size=Vector2(48,48)
		slot.tooltip_text=str(data.get("name",str(ident)))+(" · 双击卸下" if equipped else " · 双击装备" if OriginalEquipment.ITEMS.has(ident) else "")+(" · 野外可使用，满血仍消耗" if data.has("use") else "")
		Highlight.attach(slot,Rect2(Vector2(-3,1),Vector2(50,47)),selected_original_item==index)
		slot.pressed.connect(func():selected_original_item=index;selected_item_slot="original_%d" % index;rebuild())
		if OriginalEquipment.ITEMS.has(ident):
			slot.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
					world.perform_adventure_action("equip_original:%d" % int(entry.uid),not equipped)
			)
	for index in range(bag.size()+visible_originals,15):
		var empty:=choice("",Vector2(11+(index%5)*51,175+int(index/5)*48),"",null,false)
		empty.name="EmptyItemSlot_%d" % index;empty.size=Vector2(48,48)
	# Audited equipment and field consumables use server-owned commands.
	if selected_original_item>=0 and selected_original_item<originals.size():
		var data: Dictionary=quest_catalog.items.get(str(int(originals[selected_original_item])),{})
		label(str(data.get("name","")),Vector2(15,328),240,15).name="OriginalItemName"
		var description: Label
		if int(data.get("id",0))==2401 and data.has("use"):
			description=label("",Vector2(15,354),239,10)
			description.add_theme_constant_override("line_spacing",-2)
			description.text="野外回复90～110（原标示100）\n自己或随身宠物；满血仍消耗\n零HP宠物可回复；战斗道具未接入"
			description.reset_size()
			description.tooltip_text=str(data.get("description",""))
			original_recovery_buttons(profile)
		else:description=label(str(data.get("description","")),Vector2(15,354),239,14)
		description.name="OriginalItemDescription"
		var ident:=int(originals[selected_original_item])
		if OriginalEquipment.ITEMS.has(ident) and selected_original_item<instances.size():
			description.position.y=348
			description.add_theme_font_size_override("font_size",10)
			description.max_lines_visible=2
			description.tooltip_text=description.text
			var entry: Dictionary=instances[selected_original_item]
			var worn:=OriginalEquipment.worn(profile,int(entry.uid))
			var spec: Dictionary=OriginalEquipment.ITEMS[ident]
			var details:=label("等级 %d · 攻 %+d 防 %+d 敏 %+d 魅 %+d\n%s" % [int(spec.level),int(spec.attack),int(spec.defence),int(spec.speed),int(spec.charm),"无战斗磨损" if int(spec.durability)==0 else "耐久 %d / %d · %s" % [int(entry.durability),int(spec.durability),OriginalEquipment.STAGES[OriginalEquipment.stage(entry)]]],Vector2(15,374),246,11)
			details.name="OriginalEquipmentDetails"
			if ident in [2418,2427]:
				var resistance:=label("六状态耐性 +%d 尚未生效" % (3 if ident==2418 else 2),Vector2(90,410),174,10)
				resistance.name="OriginalResistanceUnavailable"
				resistance.tooltip_text="毒、麻痹、睡眠、石化、酒醉、混乱耐性各 +%d：状态战斗尚未实现，未生效" % (3 if ident==2418 else 2)
			var equip:=choice("卸下" if worn else "装备",Vector2(14,404),"equip_original:%d" % int(entry.uid),not worn)
			equip.name="EquipOriginalItem"
			if ident in [2418,2427]:equip.size.x=70
		return
	selected_original_item=-1
	var potion := selected_item=="potion"
	label(item_name(selected_item),Vector2(15,328),240,15)
	label(item_description(selected_item),Vector2(15,354),239,12 if selected_item in Spirits.SPIRIT_ITEMS else 14)
	var main := choice("使用" if potion else ("恢复宠物" if selected_item=="healing_charm" else "卸下" if item_equipped(profile,selected_item) else "装备"),Vector2(14,404),"use_potion" if potion else equip_action(selected_item),null if potion else not item_equipped(profile,selected_item),int(profile.inventory.get(selected_item,0))>0 and (not potion or int(profile.player.hp)<int(profile.player.max_hp)))
	spirit_field_buttons(profile,main)

func original_recovery_buttons(profile: Dictionary) -> void:
	if not original_use_pet_id.is_empty() and not profile.pets.any(func(pet):return str(pet.pet_id)==original_use_pet_id):original_use_pet_id=""
	var can_use:bool=int(profile.player.hp)>0 and not world.session.in_battle() and not world.battle_view.visible and not original_item_busy
	var action:=choice("使用",Vector2(14,404),"use_original_item",["original_2401",original_use_pet_id],can_use)
	action.name="OriginalItemUse";action.size.x=70
	action.tooltip_text="消耗一份香草；满血仍消耗。施药者死亡时不能使用。"
	var caption:="目标：自己"
	for pet in profile.pets:
		if str(pet.pet_id)==original_use_pet_id:caption="目标："+str(pet.name)
	var targets:=choice(caption,Vector2(88,404),"",null,not original_item_busy)
	targets.name="OriginalItemTarget";targets.size=Vector2(168,28)
	targets.add_theme_font_size_override("font_size",12)
	for connection in targets.pressed.get_connections():targets.pressed.disconnect(connection.callable)
	targets.pressed.connect(original_recovery_targets)

func original_recovery_targets() -> void:
	if original_item_busy or panel.has_node("OriginalRecoveryTargets"):return
	panel.get_node("OriginalItemUse").disabled=true
	var overlay:=pet_overlay("OriginalRecoveryTargets","使用目标","",Vector2(272,400))
	overlay_button(overlay,"返回",194,rebuild,"OriginalRecoveryBack")
	var scroll:=ScrollContainer.new();scroll.position=Vector2(12,52);scroll.size=Vector2(248,336)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var rows:=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	var choices:Array=[{"pet_id":"","name":"自己","hp":world.session.snapshot().player.hp,"max_hp":world.session.snapshot().player.max_hp}]+world.session.snapshot().pets
	for target in choices:
		var uid:String=str(target.pet_id)
		var button:Button=world.button("%s %d/%d"%[str(target.name),int(target.hp),int(target.max_hp)],func():original_use_pet_id=uid;rebuild())
		button.name="OriginalRecoveryTarget_"+("self" if uid.is_empty() else uid)
		button.custom_minimum_size=Vector2(236,32);button.add_theme_font_size_override("font_size",13)
		button.tooltip_text="自己" if uid.is_empty() else uid
		rows.add_child(button)

## The worn healing 精灵 cast outside battle (FIELD_ALL: 治愈, 滋润): on the
## player, or with 滋润 on the battle pet (the original's status window 精灵).
func spirit_field_buttons(profile: Dictionary, main: Button) -> void:
	if not selected_item in Spirits.SPIRIT_ITEMS or not item_equipped(profile,selected_item):return
	var magic := Spirits.magic_of(selected_item)
	if str(magic.kind)!="recovery" or int(magic.field)==Spirits.FIELD_BATTLE:return
	main.size.x = 70
	var slot := str(Spirits.ITEMS[selected_item].slot)
	var cost := 0 if bool(profile.get("free_spirits",true)) else int(Spirits.ITEMS[selected_item].mp)
	var enough := int(profile.player.get("mp",Spirits.MAX_MP))>=cost
	var self_cast := choice("精灵→自己",Vector2(86,404),"use_spirit",[slot,0],enough)
	self_cast.name = "SpiritOnSelf"
	self_cast.size.x = 90
	self_cast.tooltip_text = "%s，消耗气力 %d（剩 %d）" % [str(magic.name),cost,int(profile.player.get("mp",0))]
	if int(magic.target)==Spirits.TARGET_OTHER and int(profile.active_pet)>=0:
		var pet_cast := choice("→出战宠",Vector2(178,404),"use_spirit",[slot,int(profile.active_pet)+1],enough)
		pet_cast.name = "SpiritOnPet"
		pet_cast.size.x = 80
		pet_cast.tooltip_text = self_cast.tooltip_text

## 宠物技能's button (26046) with its lettering replaced by the stone face of
## its left edge, for buttons the original has no art for.
func native_blank_button() -> Texture2D:
	if art.has(-26046):return art[-26046]
	var image:=original(26046).get_image()
	image.convert(Image.FORMAT_RGBA8)
	var source: Image = image.duplicate()
	var width:=image.get_width()
	# Lettering and its outline become the face's stone speckle; stone stays.
	var stone:=[Color8(128,128,128),Color8(160,160,164),Color8(166,202,240),Color8(192,220,192)]
	for x in range(3,width-3):
		for y in range(1,image.get_height()-2):
			var c: Color = source.get_pixel(x,y)
			if not stone.any(func(s:Color):return s.is_equal_approx(Color(c.r,c.g,c.b,1.0))):
				image.set_pixel(x,y,source.get_pixel(2,y) if (x+y)%3 else Color8(160,160,164))
	art[-26046]=ImageTexture.create_from_image(image)
	return art[-26046]

func pet_native_button(ident: int, center: Vector2, callback: Callable, title: String = "") -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = original(ident)
	button.position = center-button.texture_normal.get_size()/2
	button.tooltip_text = title
	button.pressed.connect(callback)
	panel.add_child(button)
	Highlight.attach(button,Rect2(Vector2(-2,-2),button.texture_normal.get_size()+Vector2(4,4)))
	return button

func pet_switch_view(view: String) -> void:
	pet_view = view
	pet_rename = false
	world.play_ui_sound(202)
	rebuild()

func pet_panel(profile: Dictionary) -> void:
	var pets: Array = profile.pets
	var filtered := filtered_pet_indices(profile)
	if pets.is_empty() or filtered.is_empty():pet_view="list"
	selected_pet=clampi(selected_pet,0,maxi(0,pets.size()-1))
	if not filtered.is_empty() and selected_pet not in filtered:selected_pet=int(filtered[0])
	pet_collection_tools(profile,filtered)
	if pet_view=="list":
		panel.size=Vector2(272,320)
		image(26044,Vector2.ZERO)
		pet_page=clampi(pet_page,0,maxi(0,int((filtered.size()-1)/5)))
		var page_indices := filtered.slice(pet_page*5,pet_page*5+5)
		for row_index in range(page_indices.size()):
			var i := int(page_indices[row_index])
			var pet: Dictionary=pets[i]
			var active: bool=int(profile.active_pet)==i
			var y:=31+row_index*51
			var riding: bool=int(profile.get("ride_pet",-1))==i
			var color:=Color.YELLOW if active else (Color("82dfec") if riding else Color.WHITE)
			var title:=label(("[骑] " if riding else "")+str(pet.name),Vector2(69,y),155,14)
			title.add_theme_color_override("font_color",color)
			label(str(pet.level),Vector2(108,y+24),30,13).add_theme_color_override("font_color",color)
			label(str(pet.hp),Vector2(168,y+24),35,13).add_theme_color_override("font_color",color)
			label(str(pet.max_hp),Vector2(223,y+24),37,13).add_theme_color_override("font_color",color)
			var row:=Button.new()
			row.name="PetRow%d" % i
			row.position=Vector2(67,y-3)
			row.size=Vector2(190,47)
			for style in ["normal","hover","pressed","focus"]:row.add_theme_stylebox_override(style,StyleBoxEmpty.new())
			row.pressed.connect(func(): selected_pet=i; pet_switch_view("detail"))
			panel.add_child(row)
			# Source pet names are font hitFlag2: outline the name, not the whole row.
			var name_width := title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
			Highlight.attach(row,Rect2(Vector2(-1,1),Vector2(minf(name_width+5,190),22)))
			var state:=pet_native_button(26053 if active else 26052,Vector2(39,y+10),func(): world.perform_adventure_action("select_pet",-1 if active else i),"休息" if active else "出战")
			state.name="PetState%d" % i
			if world.session.in_battle():
				state.disabled=true;state.modulate=Color(1,1,1,0.5);state.tooltip_text=DEPLOY_IN_BATTLE
		if filtered.is_empty():
			label("没有此类宠物",Vector2(76,31),160,14)
			pet_native_button(26042,Vector2(136,299),world.close_adventure_menu)
		else:
			pet_native_button(26056,Vector2(80,299),func(): pet_switch_view("detail"),"详细资料")
			pet_native_button(26042,Vector2(192,299),world.close_adventure_menu)
		return
	var pet: Dictionary=pets[selected_pet]
	if pet_view=="skills":
		panel.size=Vector2(272,348)
		image(26130,Vector2.ZERO)
		var skills:=PackedStringArray(["待机","攻击","防御"])
		for skill in pet.get("learned_skills",[]):skills.append(preload("res://scripts/pet_skills.gd").SKILLS[int(skill)].name)
		var ui_metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json")).ui
		for i in range(skills.size()):
			var bar: Dictionary=ui_metadata[str(26131+i)]
			image(26131+i,Vector2(136+bar.x,174+bar.y))
			label(skills[i],Vector2(70,58+i*25),185,14)
		label(pet.name,Vector2(13,32),220,14)
		pet_native_button(26043,Vector2(190,330),func(): pet_switch_view("detail"))
		pet_navigation(pets.size(),330)
		return
	panel.size=Vector2(272,332)
	image(26045,Vector2.ZERO)
	label(pet.name,Vector2(13,35),150,14)
	pet_native_button(26058,Vector2(86,66),func(): pet_rename=true; rebuild(),"更改名字")
	var values := [str(pet.level),str(pet.xp),str(int(pet.level)*30-int(pet.xp))]
	for i in range(3):label(values[i],Vector2(70,82+i*24),80,13)
	label(str(pet.hp),Vector2(66,154),41,13)
	label(str(pet.max_hp),Vector2(113,154),45,13)
	for i in range(4):
		var value:=str([pet.attack,pet.defence,pet.speed,pet.get("loyalty","—")][i])
		label(value,Vector2(70,178+i*24),45,13)
	# menu.cpp:15215: 属性 bars beside the four stat rows (x+159, y+5).
	var pet_elements := Elements.of(pet)
	ElementBars.add(panel,pet_elements,Vector2(179,183),24)
	var element_hint := Control.new()
	element_hint.name = "PetElements"
	element_hint.position = Vector2(178,180)
	element_hint.size = Vector2(84,88)
	element_hint.tooltip_text = "属性：%s" % Elements.text(pet_elements)
	panel.add_child(element_hint)
	# menu.cpp:12777 MakeAnimDisp(x+200,y+144,graNo,ANIM_DISP_PET): the standing
	# loop, first facing 1 (menu.cpp:1881); a click turns it (menu.cpp:1177).
	var portrait_view:=AnimatedPortrait.new()
	portrait_view.name="PetPortrait"
	portrait_view.position=Vector2(200,144)
	panel.add_child(portrait_view)
	portrait_view.setup(str(int(pet.sprite)),pet_portrait_facing,func(facing:int):
		pet_portrait_facing=facing
		world.play_battle_sound(217))
	pet_native_button(26046,Vector2(198,286),func(): pet_switch_view("skills"),"宠物技能")
	# 存入仓库 beside 宠物技能, drawn like the original buttons (stone face,
	# green text with a dark outline) on a face cut from 宠物技能's art.
	var stash:=TextureButton.new()
	stash.name="PetStatusStore"
	stash.texture_normal=native_blank_button()
	stash.position=Vector2(90,286)-stash.texture_normal.get_size()/2
	var stash_text:=Label.new()
	stash_text.text="存入仓库"
	stash_text.size=stash.texture_normal.get_size()
	stash_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	stash_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	stash_text.add_theme_font_size_override("font_size",13)
	stash_text.add_theme_color_override("font_color",Color8(40,225,40))
	stash_text.add_theme_color_override("font_outline_color",Color8(40,35,30))
	stash_text.add_theme_constant_override("outline_size",4)
	stash_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stash.add_child(stash_text)
	stash.pressed.connect(func():
		var shown:=selected_pet
		if world.session.store_pet(shown):
			world.refresh_companion();world.checkpoint();feedback="已存入仓库。"
			selected_pet=clampi(shown,0,maxi(0,world.session.snapshot().pets.size()-1))
		else:feedback=world.session.last_error
		rebuild())
	var stash_lock:=battle_lock(str(pet.get("pet_id","")),"存入仓库")
	if selected_pet==int(world.session.snapshot().get("ride_pet",-1)):stash_lock="骑乘中的宠物不能存入仓库，请先下骑。"
	stash.disabled=not stash_lock.is_empty()
	stash.tooltip_text=stash_lock if stash.disabled else "把这只宠物存入仓库"
	if stash.disabled:stash.modulate=Color(1,1,1,0.45)
	panel.add_child(stash)
	Highlight.attach(stash,Rect2(Vector2(-2,-2),stash.texture_normal.get_size()+Vector2(4,4)))
	pet_native_button(26043,Vector2(190,317),func(): pet_switch_view("list"))
	pet_navigation(pets.size(),317)
	if pet_rename:pet_rename_panel(pet)

func pet_navigation(_count: int, y: float) -> void:
	var indices := filtered_pet_indices(world.session.snapshot())
	if indices.is_empty():return
	var position := maxi(0,indices.find(selected_pet))
	pet_native_button(26180,Vector2(60,y),func(): selected_pet=int(indices[(position+indices.size()-1)%indices.size()]); rebuild(),"上一只")
	pet_native_button(26182,Vector2(104,y),func(): selected_pet=int(indices[(position+1)%indices.size()]); rebuild(),"下一只")

const DEPLOY_IN_BATTLE:="战斗中不能更换出战宠物，请用战斗里的「宠物」指令。"

## During a battle: why this pet cannot be released, stored or withdrawn
## ("" when it can). The backend (GameSession.battle_pets) decides; this only
## greys the buttons and explains. what: 放生 or 存入仓库.
func battle_lock(pet_id: String, what: String) -> String:
	var reason:=str(world.session.battle_pets().get(pet_id,""))
	return "" if reason.is_empty() else "正在战斗中（%s），战斗结束后才能%s。" % [reason,what]

func filtered_pet_indices(profile: Dictionary) -> Array:
	var result := []
	for i in range(profile.pets.size()):
		if pet_category=="全部" or PetGrowth.category(profile.pets[i])==pet_category:result.append(i)
	return result

func pet_tool_button(caption: String, at: Vector2, callback: Callable, control_name: String) -> Button:
	var control: Button = world.button(caption,callback)
	control.name=control_name
	control.position=at
	control.custom_minimum_size=Vector2(220,28)
	panel.add_child(control)
	return control

## Ride or dismount the selected pet. Disabled, with the rule's reason below it,
## when the current character cannot ride that pet (riding.gd can_mount).
func pet_mount_button(profile: Dictionary, at: Vector2) -> Button:
	var pet: Dictionary = profile.pets[selected_pet]
	var riding:=int(profile.get("ride_pet",-1))==selected_pet
	var reason:="" if riding else Riding.can_mount(profile,selected_pet)
	if world.session.in_battle():reason="战斗中不能骑乘或下骑。"
	var control:=pet_tool_button(("下骑 · " if riding else "骑乘 · ")+str(pet.name),at,func():
		if world.session.mount_pet(-1 if riding else selected_pet):
			world.refresh_companion();world.checkpoint();feedback=""
		else:feedback=world.session.last_error
		rebuild(),"PetMount")
	control.disabled=not reason.is_empty()
	control.tooltip_text=reason
	if not reason.is_empty():
		var note:=label(reason,at+Vector2(0,174),230,12)
		note.name="PetMountReason"
		note.add_theme_color_override("font_color",Color("ffd080"))
	return control

func pet_collection_tools(profile: Dictionary, filtered: Array) -> void:
	var origin:=Vector2(288,0)
	stone(Rect2(origin,Vector2(256,480)))
	label("宠物收藏 · %d / %d" % [profile.pets.size(),world.session.PET_CAPACITY],origin+Vector2(16,14),235,16)
	var categories := ["全部","人龙","老虎","暴龙","乌力","其他"]
	var selector:=OptionButton.new()
	selector.name="PetCategory"
	selector.position=origin+Vector2(16,47)
	selector.size=Vector2(220,30)
	for category in categories:selector.add_item(category)
	selector.select(categories.find(pet_category))
	selector.item_selected.connect(func(index:int):pet_category=categories[index];pet_page=0;pet_view="list";rebuild())
	panel.add_child(selector)
	var pages:=maxi(1,int(ceil(filtered.size()/5.0)))
	pet_page=clampi(pet_page,0,pages-1)
	label("第 %d / %d 页 · %d 只" % [pet_page+1,pages,filtered.size()],origin+Vector2(16,88),230,14)
	pet_native_button(26180,origin+Vector2(40,126),func(): change_pet_page(-1,filtered),"上一页")
	pet_native_button(26182,origin+Vector2(112,126),func(): change_pet_page(1,filtered),"下一页")
	label("黄色：出战　蓝色：[骑] 骑乘",origin+Vector2(16,154),230,12)
	if not filtered.is_empty():
		pet_tool_button("成长预估" if not pet_growth_open else "关闭成长预估",origin+Vector2(16,182),func(): pet_growth_open=not pet_growth_open;pet_view="detail";rebuild(),"PetGrowthToggle")
		pet_mount_button(profile,origin+Vector2(16,218))
	pet_tool_button("DEV · 领取起始伙伴",origin+Vector2(16,254),func():
		if world.session.grant_starter_pets():
			world.refresh_companion();world.checkpoint();feedback="起始伙伴已加入（重复领取不增加）。"
		else:feedback="空间不足或当前不能领取。"
		rebuild(),"StarterPets")
	label(feedback,origin+Vector2(16,436),230,12)
	pet_tool_button("宠物记录",origin+Vector2(16,362),func():open_pet_records("",-1),"PetRecords")
	var hunt:=pet_tool_button("自动抓极品",origin+Vector2(16,398),func():world.close_adventure_menu();world.pet_hunt_menu.open_menu(),"PetHunt");hunt.custom_minimum_size.x=108
	if world.battle_view.visible:hunt.disabled=true;hunt.tooltip_text="战斗结束后才能打开。"
	# 宠物大全, where the player left it.
	pet_tool_button("宠物大全",origin+Vector2(128,398),func():
		world.close_adventure_menu();world.pet_encyclopedia.open_menu(),"PetEncyclopedia").custom_minimum_size.x=108
	pet_tool_button("宠物仓库",origin+Vector2(16,326),func():pet_storage_target_id=str(profile.pets[selected_pet].get("pet_id","")) if not profile.pets.is_empty() else "";pet_storage_open=true;pet_compare_open=false;rebuild(),"PetStorage")
	if not filtered.is_empty():
		pet_tool_button("同种比较",origin+Vector2(16,290),func():pet_compare_subject=profile.pets[selected_pet].duplicate(true);pet_compare_open=true;rebuild(),"PetCompare")
	if pet_growth_open and not filtered.is_empty():pet_growth_panel(profile.pets[selected_pet],Vector2(576,0))

func change_pet_page(delta:int,indices:Array)->void:
	var pages:=maxi(1,int(ceil(indices.size()/5.0)))
	pet_page=(pet_page+delta+pages)%pages
	if not indices.is_empty():selected_pet=int(indices[pet_page*5])
	pet_view="list"
	pet_growth_open=false
	rebuild()

func pet_growth_panel(pet: Dictionary, origin: Vector2) -> void:
	# Comparison level120 is a project choice, not the reference's level cap140.
	stone(Rect2(Vector2(560,0),Vector2(384,336)))
	var forecast:=PetGrowth.forecast(pet,120)
	if forecast.is_empty():
		label("缺少原始成长资料",origin,340,14)
		return
	var at_target:=int(pet.level)>=120
	# Growth is seeded per pet and level, so the Lv.120 result is exact, not a range.
	var final:Dictionary=pet if at_target else PetComparison.expected(pet)
	label("ID %s" % str(pet.get("pet_id","?")),origin+Vector2(0,2),350,11).name="PetGrowthIdentity"
	label(("%s · Lv.%d 当前能力" % [pet.name,pet.level]) if at_target else "%s · Lv.%d → %d 精确推算" % [pet.name,pet.level,forecast.target_level],origin+Vector2(0,20),350,15).name="PetGrowthHeading"
	var average:Dictionary=forecast.species_average
	for column in [["属性",0],["当前" if at_target else "120级",66],["较均值",128],["同种均值",257]]:
		label(column[0],origin+Vector2(column[1],54),85,14)
	var keys: Array = ["max_hp","attack","defence","speed"]
	var names: Array = ["体力","攻击","防御","敏捷"]
	for i in range(4):
		var key:String=keys[i]
		var value:=int(final.get(key,forecast.expected[key]))
		var typical:=int(average.get(key,0))
		var y:=86+i*25
		label(names[i],origin+Vector2(0,y),50,14)
		label(str(value),origin+Vector2(66,y),60,14)
		label("%+d" % (value-typical),origin+Vector2(128,y),125,13)
		var comparison:=label(str(typical) if not average.is_empty() else "—",origin+Vector2(257,y),90,14)
		comparison.mouse_filter=Control.MOUSE_FILTER_PASS
		comparison.tooltip_text="同种普通出生、从 Lv.1 培养的平均值。理论单项上限 %s；各项极限不能同时达到，不能作为正常品质标准。" % str(forecast.species_maximum.get(key,"未知"))
	var gains:Dictionary=forecast.base_increment
	label("每级基础成长：体 %.3f　腕 %.3f\n                         耐 %.3f　速 %.3f" % [gains.vitality,gains.strength,gains.toughness,gains.dexterity],origin+Vector2(0,196),350,13)
	var innate:=PetComparison.quality(pet)
	var innate_text:="先天档未知" if innate.is_empty() else "先天 体%+d 腕%+d 耐%+d 速%+d · 总%+d%s" % [innate.offsets[0],innate.offsets[1],innate.offsets[2],innate.offsets[3],innate.total," 满档" if innate.full else ""]
	label(innate_text,origin+Vector2(0,240),350,12).name="PetInnateQuality"
	label("同种均值：从 Lv.1 正常培养，非极限。\n"+("已达目标级，显示当前结果。" if at_target else "范围为单项近似90%；不能保证同时落入。"),origin+Vector2(0,268),350,12)
	var modified:bool=bool(pet.get("gm_modified",false)) or pet.get("legacy_stat_offset",{}).values().any(func(value):return float(value)!=0.0)
	label("含 GM／旧档修正，不用于天然品质比较。" if modified else "按原版随机规则；接近目标级时范围较粗略。",origin+Vector2(0,310),350,11)

func pet_rename_panel(pet: Dictionary) -> void:
	var origin:=Vector2(0,336)
	image(26049,origin)
	name_edit=LineEdit.new()
	name_edit.text=pet.name
	name_edit.max_length=16
	name_edit.position=origin+Vector2(18,20)
	name_edit.size=Vector2(148,23)
	name_edit.add_theme_font_size_override("font_size",14)
	name_edit.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	panel.add_child(name_edit)
	pet_native_button(26093,origin+Vector2(80,67),func(): world.perform_adventure_action("rename_pet",selected_pet); pet_rename=false; rebuild(),"确定")
	pet_native_button(26050,origin+Vector2(190,67),func(): pet_rename=false; rebuild(),"取消")

func shop_panel(profile: Dictionary) -> void:
	image(26138,Vector2.ZERO)
	label("萨姆吉尔的道具店",Vector2(121,13),220,17)
	label("需要什么呢？",Vector2(18,53),200,15)
	label("石币 %d" % profile.player.gold,Vector2(235,73),185,14)
	if not selected_item in SHOP:selected_item = "potion"
	for i in range(SHOP.size()):
		var key: String = SHOP[i]
		# Two columns of four rows (the stock outgrew one column).
		var at := Vector2(18+int(i/4)*205,111+(i%4)*48)
		var icon := item_icon(key,Vector2.ZERO)
		if icon.texture!=null:icon.position = at+Vector2(24,22)-icon.texture.get_size()/2
		label(item_name(key),at+Vector2(50,0),150,14)
		label("%d 石币 · 持有 %d" % [int(GameSessionScript.ITEM_PRICES.get(key,0)),int(profile.inventory.get(key,0))],at+Vector2(50,22),150,12)
		var row:=choice("",at,"",null)
		for connection in row.pressed.get_connections():row.pressed.disconnect(connection.callable)
		row.name = "ShopRow_"+key
		row.size=Vector2(200,46)
		Highlight.attach(row,Rect2(Vector2(-1,-1),Vector2(202,48)),selected_item==key)
		row.pressed.connect(func(): selected_item=key;rebuild())
	item_icon(selected_item,Vector2(43,319))
	label(item_name(selected_item)+(" · 镜之精灵" if selected_item=="mirror_charm" else " · "+item_description(selected_item)),Vector2(111,305),300,12)
	label("售出 %d 石币" % int(int(GameSessionScript.ITEM_PRICES.get(selected_item,0))/2),Vector2(111,352),200,14)
	art_button(26098,Vector2(231,382),"buy_"+selected_item,null,int(profile.player.gold)>=int(GameSessionScript.ITEM_PRICES.get(selected_item,0))).tooltip_text="购买一个"

	art_button(26097,Vector2(312,382),"sell_"+selected_item,null,int(profile.inventory.get(selected_item,0))>0 and (not item_equipped(profile,selected_item) or int(profile.inventory.get(selected_item,0))>1)).tooltip_text="卖出一个"

func style_pet_modal(root_control:Control)->void:
	if readable_font==null:
		readable_font=FontVariation.new();readable_font.base_font=load("res://assets/fonts/NotoSansSC.ttf");readable_font.variation_opentype={2003265652:600.0}
	# PetTable roles set their own fonts; only unstyled controls get the default.
	for node in root_control.find_children("*","Control",true,false):
		if node.has_meta("sort_header"):continue
		if node is CheckBox:PetTable.style_checkbox(node)
		elif node is OptionButton:
			node.add_theme_font_override("font",PetTable.font(500));node.add_theme_font_size_override("font_size",13)
			node.get_popup().add_theme_font_override("font",PetTable.font(500))
		elif node is Button:
			PetTable.style_button(node,node.has_meta("compact"))
			if str(node.name).begins_with("RecordsTab") and node.button_pressed:
				node.add_theme_color_override("font_color",PetTable.GOLD)
				node.add_theme_color_override("font_pressed_color",PetTable.GOLD)
		elif not node.has_theme_font_override("font"):node.add_theme_font_override("font",readable_font)

## A pet-table overlay: bordered panel with a title, a muted subtitle and the
## header buttons, right to left from `right`.
func pet_overlay(overlay_name:String,title:String,subtitle:String,panel_size:Vector2)->Panel:
	var overlay:=Panel.new();overlay.name=overlay_name;overlay.position=Vector2.ZERO;overlay.z_index=10;overlay.mouse_filter=Control.MOUSE_FILTER_STOP;overlay.size=panel_size
	overlay.add_theme_stylebox_override("panel",world.box(Color("182324"),PetTable.EDGE));panel.add_child(overlay)
	var heading:=HBoxContainer.new();heading.position=Vector2(14,10);heading.add_theme_constant_override("separation",10);overlay.add_child(heading)
	heading.add_child(PetTable.text(title,"title"))
	var sub:=PetTable.text(subtitle,"meta");sub.size_flags_vertical=Control.SIZE_SHRINK_END;heading.add_child(sub)
	return overlay

func overlay_button(overlay:Control,caption:String,x:float,callback:Callable,control_name:String="")->Button:
	var control:Button=world.button(caption,callback);control.position=Vector2(x,10)
	if not control_name.is_empty():control.name=control_name
	overlay.add_child(control)
	return control

## The row's text as one description: the row tooltip (and what tests read).
static func compare_description(pet:Dictionary,estimate:Dictionary,q:Dictionary,location:String,identifier:String,rule_line:String)->String:
	var stats_line:="当前 血%d 攻%d 防%d 敏%d · 三围合%d" % [pet.max_hp,pet.attack,pet.defence,pet.speed,int(pet.attack)+int(pet.defence)+int(pet.speed)]
	if int(pet.level)<120:stats_line+="\n120级 血%d 攻%d 防%d 敏%d · 三围合%d" % [estimate.max_hp,estimate.attack,estimate.defence,estimate.speed,int(estimate.attack)+int(estimate.defence)+int(estimate.speed)]
	if not rule_line.is_empty():stats_line+="\n"+rule_line
	return "%s · Lv.%d · %s · ID %s\n%s\n先天 %s%s" % [pet.name,pet.level,"携带" if location=="pets" else "仓库",identifier,stats_line,"未知" if q.is_empty() else str(q.offsets)+" 总%+d"%q.total+(" 满档" if q.full else "")," · GM／旧档，不作天然品质判断" if PetComparison.warning(pet) else ""]

## Width before the first stat column in 同种比较 rows: 选, ★ and the name block.
const COMPARE_LEAD:=234.0 # 选 24 + ★ 26 + name 172 + two separators
const COMPARE_NAME:=172.0

func pet_comparison_panel(profile:Dictionary,selected:Dictionary)->void:
	var rows:=PetComparison.rows(profile,selected,pet_compare_order,pet_compare_projected,pet_compare_favorites_first,pet_compare_carried_first)
	var overlay:=pet_overlay("PetComparisonPanel","同种比较 · "+str(selected.name),"携带与仓库 · %d只"%rows.size(),Vector2(900,650))
	overlay_button(overlay,"关闭",832,func():pet_compare_open=false;pet_view="list";clear_release_selection();rebuild())
	if PetComparison.species_key(selected)!=pet_release_species:
		clear_release_selection();pet_release_species=PetComparison.species_key(selected)
	overlay_button(overlay,"自动抓极品",722,func():continue_comparison_hunt(selected),"CompareContinueHunt")
	var species_key:=PetComparison.species_key(selected)
	overlay_button(overlay,"宠物记录",626,func():open_pet_records("",int(species_key.trim_prefix("original_")) if species_key.trim_prefix("original_").is_valid_int() else -1),"CompareRecords")
	load_compare_prefs()
	compare_sort_controls(overlay)
	var workflow_note:bool=is_instance_valid(world.pet_workflow) and world.pet_workflow.phase=="compare" and world.pet_workflow.pet_id==str(selected.get("pet_id",""))
	var info:=PetTable.text(world.pet_workflow.reason if workflow_note else (feedback if not feedback.is_empty() else "未满级宠物按成长种子精确推算120级属性，可跨等级比较。"),"meta",PetTable.TEXT if workflow_note or not feedback.is_empty() else null)
	info.name="PetComparisonInfo";info.position=Vector2(14,84);info.clip_text=true;info.mouse_filter=Control.MOUSE_FILTER_PASS
	info.tooltip_text=info.text+("\n"+feedback_tooltip if not feedback_tooltip.is_empty() else "")
	# A find-pet cycle's result can be long: up to three lines above the cards.
	if workflow_note:info.text=PetTable.fit_lines(info.text,"meta",660,3)
	overlay.add_child(info)
	info.size=Vector2(670,52) if workflow_note else Vector2(640,20)
	var pages:=maxi(1,ceili(rows.size()/20.0));pet_compare_page=clampi(pet_compare_page,0,pages-1)
	var previous:Button=world.button("◀",func():pet_compare_page=maxi(0,pet_compare_page-1);rebuild());previous.position=Vector2(700,78);overlay.add_child(previous)
	var page:=PetTable.text("%d / %d 页"%[pet_compare_page+1,pages],"meta");page.position=Vector2(742,84);page.size.x=100;page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;overlay.add_child(page)
	var next:Button=world.button("▶",func():pet_compare_page=mini(pages-1,pet_compare_page+1);rebuild());next.position=Vector2(852,78);overlay.add_child(next)
	var shown:=func(row:Dictionary)->Dictionary:return row.forecast.get("expected",row.pet) if pet_compare_projected else row.pet
	var best:=PetTable.best_values(rows.map(shown))
	# Pinned cards: the selected pet and the leader of the current order.
	var focus_id:=str(selected.get("pet_id",""))
	var focus:Dictionary=selected
	for row in rows:
		if str(row.pet.get("pet_id",""))==focus_id:focus=row.pet
	var leader:Dictionary=rows[0].pet if not rows.is_empty() else focus
	var top:=144.0 if workflow_note else 112.0
	for entry in [["选中",focus],["当前分组首位",leader]]:
		var actor:Dictionary=entry[1]
		var caption:String="当前首位" if entry[0]=="当前分组首位" and not pet_compare_carried_first else str(entry[0])
		var pinned:=PetTable.card();pinned.name="ComparePinned_"+str(entry[0]);pinned.position=Vector2(12,top);pinned.custom_minimum_size=Vector2(876,0);overlay.add_child(pinned)
		pinned.tooltip_text="%s %s · %s Lv.%d\n当前 血%d 攻%d 防%d 敏%d · 三围合%d" % [caption,actor.get("pet_id","?"),actor.name,actor.level,actor.max_hp,actor.attack,actor.defence,actor.speed,int(actor.attack)+int(actor.defence)+int(actor.speed)]
		pinned.mouse_filter=Control.MOUSE_FILTER_PASS
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",6);pinned.add_child(line)
		var tag:=PetTable.text(caption,"head",PetTable.GOLD);tag.custom_minimum_size.x=84;line.add_child(tag)
		var who:=PetTable.text("%s  %s"%[actor.name,actor.get("pet_id","?")],"body");who.custom_minimum_size.x=COMPARE_LEAD-84-6;who.clip_text=true;line.add_child(who)
		PetTable.stat_cells(line,actor,best)
		line.add_child(PetTable.grade(PetComparison.quality(actor)))
		top+=34
	var header:=PetTable.header(COMPARE_LEAD,["操作"]);header.position=Vector2(18,top+2);overlay.add_child(header)
	var scroll:=ScrollContainer.new();scroll.position=Vector2(12,top+24);scroll.size=Vector2(876,650-(top+24)-92);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",2);scroll.add_child(list)
	release_controls(overlay,profile,rows,scroll.position.y+scroll.size.y+8)
	var last_group:=""
	var shade:=0
	for row in rows.slice(pet_compare_page*20,(pet_compare_page+1)*20):
		# One ranking of both places has no group headings; each row says 携带 or 仓库.
		if pet_compare_carried_first and str(row.location)!=last_group:
			last_group=str(row.location);shade=0
			if list.get_child_count()>0:
				var gap:=Control.new();gap.custom_minimum_size.y=8;list.add_child(gap)
			var heading:=PetTable.text("随身宠物" if last_group=="pets" else "仓库宠物","section");heading.name="CompareGroup_"+last_group;list.add_child(heading)
		var pet:Dictionary=row.pet;var estimate:Dictionary=row.forecast.get("expected",pet);var q:Dictionary=row.quality
		var identifier:=str(pet.get("pet_id",str(row.location)+"#"+str(row.index+1)))
		var rule_line:=""
		if pet_rule_reasons.has(identifier):rule_line=KeepRule.describe(pet_rule_reasons[identifier])+("（按120级推算）" if int(pet.level)<120 else "")
		var focused:=identifier==focus_id
		var holder:=PetTable.row_panel(shade,focused);shade+=1
		holder.name="CompareRow_"+str(row.location)+"_"+str(row.index)
		holder.tooltip_text=("▶ 当前选中 · " if focused else "")+compare_description(pet,estimate,q,row.location,identifier,rule_line)
		holder.mouse_filter=Control.MOUSE_FILTER_PASS
		list.add_child(holder)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",6);holder.add_child(line)
		var pick:=CheckBox.new();pick.name="CompareSelect_"+identifier;pick.focus_mode=Control.FOCUS_NONE;pick.button_pressed=pet_release_selected.has(identifier);pick.tooltip_text="选中（放生用）";pick.custom_minimum_size.x=24
		var fighting:=battle_lock(identifier,"放生")
		if not fighting.is_empty():pick.disabled=true;pick.tooltip_text=fighting
		pick.toggled.connect(func(on):
			if on:pet_release_selected[identifier]=true
			else:pet_release_selected.erase(identifier)
			pet_release_confirm=false;rebuild());line.add_child(pick)
		add_pet_favorite_button(line,pet,"CompareFavorite_")
		var who:=VBoxContainer.new();who.custom_minimum_size.x=COMPARE_NAME;who.add_theme_constant_override("separation",-2);line.add_child(who)
		var title:=PetTable.text(("▶ " if focused else "")+str(pet.name),"name",PetTable.GOLD if focused else null);title.clip_text=true;title.custom_minimum_size.x=COMPARE_NAME;who.add_child(title)
		var where:=identifier+" · "+("随身" if row.location=="pets" else "仓库")
		if row.location=="pets" and int(row.index)==int(profile.active_pet):where+=" · 出战"
		if row.location=="pets" and int(row.index)==int(profile.get("ride_pet",-1)):where+=" · 骑乘"
		if PetComparison.warning(pet):where+=" · GM"
		if not fighting.is_empty():where+=" · 战斗中"
		var meta:=PetTable.text(where,"meta");meta.clip_text=true;meta.custom_minimum_size.x=COMPARE_NAME;who.add_child(meta)
		if not rule_line.is_empty():
			var verdict:=PetTable.text(rule_line,"meta",PetTable.GOOD if not pet_rule_reasons[identifier].is_empty() else PetTable.BAD);verdict.clip_text=true;verdict.custom_minimum_size.x=COMPARE_NAME;verdict.tooltip_text=rule_line;verdict.mouse_filter=Control.MOUSE_FILTER_PASS;who.add_child(verdict)
		var cells:Dictionary=estimate if pet_compare_projected else pet
		PetTable.stat_cells(line,cells,best,estimate if int(pet.level)<120 and not pet_compare_projected else {})
		line.add_child(PetTable.grade(q))
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",4);actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(actions)
		var transfer:Button=world.button("存入仓库" if row.location=="pets" else "取出",func():
			var ok:bool=world.session.store_pet(int(row.index)) if row.location=="pets" else world.session.retrieve_pet_by_id(identifier)
			if ok:world.refresh_companion();world.checkpoint();feedback="已更新宠物位置。"
			else:feedback=world.session.last_error
			rebuild());transfer.name="CompareTransfer_"+identifier;transfer.disabled=(row.location=="pets" and int(row.index)==int(profile.get("ride_pet",-1))) or (row.location!="pets" and profile.pets.size()>=world.session.PET_CAPACITY);transfer.set_meta("compact",true);actions.add_child(transfer)
		if row.location=="pets" and not fighting.is_empty():transfer.disabled=true;transfer.tooltip_text=battle_lock(identifier,"存入仓库")
		if row.location=="pets":
			var deploy:Button=world.button("撤回" if int(row.index)==int(profile.active_pet) else "出战",func():
				if world.session.select_pet(-1 if int(row.index)==int(profile.active_pet) else int(row.index)):world.refresh_companion();world.checkpoint()
				else:feedback=world.session.last_error
				rebuild());deploy.name="CompareDeploy_"+identifier;deploy.set_meta("compact",true);actions.add_child(deploy)
			if world.session.in_battle():deploy.disabled=true;deploy.tooltip_text=DEPLOY_IN_BATTLE
			if int(row.index)==int(profile.get("ride_pet",-1)):
				var dismount:Button=world.button("下骑",func():
					if world.session.mount_pet(-1):world.refresh_companion();world.checkpoint()
					rebuild());dismount.name="CompareDismount_"+identifier;dismount.set_meta("compact",true);actions.add_child(dismount)
				if world.session.in_battle():dismount.disabled=true;dismount.tooltip_text="战斗中不能骑乘或下骑。"

	style_pet_modal(overlay)

func load_compare_prefs()->void:
	if _compare_prefs_loaded:return
	_compare_prefs_loaded=true
	var saved=world.viewer_pref("compare_order",PetComparison.DEFAULT_ORDER)
	pet_compare_order=(saved as Array).filter(func(key):return PetComparison.SORT_KEYS.has(key)) if saved is Array else []
	if pet_compare_order.is_empty():pet_compare_order=PetComparison.DEFAULT_ORDER.duplicate()
	pet_compare_favorites_first=bool(world.viewer_pref("compare_favorites_first",true))
	pet_compare_carried_first=bool(world.viewer_pref("compare_carried_first",true))
	storage_order=str(world.viewer_pref("storage_order",""))
	if not storage_order in PetComparison.STORAGE_KEYS:storage_order=""
	var direction=world.viewer_pref("storage_ascending",false)
	storage_ascending=direction if direction is bool else false
	var species=world.viewer_pref("storage_species","")
	storage_species=species if species is String else ""
	var favorites=world.viewer_pref("storage_favorites_first",true)
	storage_favorites_first=favorites if favorites is bool else true

## Sets the 同种比较 order (repeats dropped, at least one key) and remembers it on this device.
func set_compare_order(order:Array)->void:
	var cleaned:=[]
	for key in order:
		if PetComparison.SORT_KEYS.has(key) and not cleaned.has(key):cleaned.append(key)
	if cleaned.is_empty():cleaned=PetComparison.DEFAULT_ORDER.duplicate()
	pet_compare_order=cleaned
	world.set_viewer_pref("compare_order",cleaned)
	rebuild()

func set_compare_carried_first(on:bool)->void:
	pet_compare_carried_first=on
	world.set_viewer_pref("compare_carried_first",on)
	rebuild()

func set_compare_favorites_first(on:bool)->void:
	pet_compare_favorites_first=on
	world.set_viewer_pref("compare_favorites_first",on)
	rebuild()

## 排序 第一..第四 (later ones may be 无), 收藏优先, 按120级属性 and 随身在前.
## Keys left out still break ties in PetComparison.SORT_KEYS order.
func compare_sort_controls(overlay:Control)->void:
	var label_sort:=PetTable.text("排序","head");label_sort.position=Vector2(14,52);overlay.add_child(label_sort)
	var keys:Array=PetComparison.SORT_KEYS
	for slot in range(4):
		var pick:=OptionButton.new();pick.name="PetCompareSort%d"%(slot+1);pick.position=Vector2(50+slot*92,44);pick.custom_minimum_size.x=88;pick.focus_mode=Control.FOCUS_NONE
		pick.tooltip_text="第%s排序" % ["一","二","三","四"][slot]
		if slot>0:pick.add_item("无")
		for key in keys:pick.add_item(PetComparison.SORT_NAMES[key])
		var current:String=str(pet_compare_order[slot]) if slot<pet_compare_order.size() else ""
		pick.select(keys.find(current)+(1 if slot>0 else 0) if not current.is_empty() else 0)
		pick.item_selected.connect(func(index:int):
			var order:=pet_compare_order.duplicate()
			var chosen:String="" if slot>0 and index==0 else str(keys[index-(1 if slot>0 else 0)])
			while order.size()<=slot:order.append("")
			order[slot]=chosen
			# 无 ends the list: later picks are dropped with it.
			if chosen.is_empty():order.resize(slot)
			set_compare_order(order.filter(func(key):return not str(key).is_empty())))
		overlay.add_child(pick)
	var toggles:=[["PetCompareFavoritesFirst","收藏优先","每组里收藏的宠物排在前面",pet_compare_favorites_first,set_compare_favorites_first],
		["PetCompareProjected","按120级属性","按120级属性排序（未满级宠物按成长种子精确推算）",pet_compare_projected,func(on):pet_compare_projected=on;rebuild()],
		["PetCompareCarriedFirst","随身在前","随身宠物单独排在仓库宠物前面；关掉后两处一起排名",pet_compare_carried_first,set_compare_carried_first]]
	var x:=430.0
	for toggle in toggles:
		var box:=CheckBox.new();box.name=toggle[0];box.text=toggle[1];box.tooltip_text=toggle[2];box.position=Vector2(x,46);box.focus_mode=Control.FOCUS_NONE
		box.button_pressed=toggle[3];box.toggled.connect(toggle[4]);overlay.add_child(box)
		x+=34+toggle[1].length()*14

func clear_release_selection()->void:
	pet_release_selected.clear();pet_release_confirm=false;pet_rule_reasons.clear();feedback_tooltip=""

func release_metric_value(pet:Dictionary,metric:String)->int:
	if metric=="stat_total":return int(pet.attack)+int(pet.defence)+int(pet.speed)
	return int(pet.get(metric,0))

func release_controls(overlay:Control,profile:Dictionary,rows:Array,top:float)->void:
	var bar:=HBoxContainer.new();bar.name="CompareReleaseBar";bar.position=Vector2(14,top);bar.add_theme_constant_override("separation",8);overlay.add_child(bar)
	var count:=PetTable.text("已选 %d 只"%pet_release_selected.size(),"body");count.name="CompareSelectedCount";count.custom_minimum_size.x=70;count.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bar.add_child(count)
	var page_all:Button=world.button("本页全选",func():
		for row in rows.slice(pet_compare_page*20,(pet_compare_page+1)*20):pet_release_selected[str(row.pet.get("pet_id",""))]=true
		pet_release_confirm=false;rebuild());page_all.name="CompareSelectPage";bar.add_child(page_all)
	var clear:Button=world.button("清除选择",func():clear_release_selection();rebuild());clear.name="CompareClearSelection";bar.add_child(clear)
	if pet_release_confirm:
		var confirm:Button=world.button("确认放生 %d 只"%pet_release_selected.size(),func():perform_release());confirm.name="CompareReleaseConfirm";bar.add_child(confirm)
		var cancel:Button=world.button("取消",func():pet_release_confirm=false;rebuild());cancel.name="CompareReleaseCancel";bar.add_child(cancel)
	else:
		var release:Button=world.button("放生所选 (%d)"%pet_release_selected.size(),func():
			if not pet_release_selected.is_empty():pet_release_confirm=true
			rebuild());release.name="CompareRelease";release.disabled=pet_release_selected.is_empty();release.tooltip_text="永久删除所选宠物；收藏、出战、骑乘的宠物会跳过。放生前自动备份存档，并记入宠物记录的「放生」。";bar.add_child(release)
	var picker:=HBoxContainer.new();picker.name="CompareThresholdBar";picker.position=Vector2(14,top+40);picker.add_theme_constant_override("separation",8);overlay.add_child(picker)
	var pick_label:=PetTable.text("选中","body");pick_label.size_flags_vertical=Control.SIZE_SHRINK_CENTER;picker.add_child(pick_label)
	var metric:=OptionButton.new();metric.name="CompareThresholdMetric";metric.focus_mode=Control.FOCUS_NONE
	for caption in ["三围合","攻击","防御","敏捷"]:metric.add_item(caption)
	metric.select(pet_release_metric);metric.item_selected.connect(func(i):pet_release_metric=i);picker.add_child(metric)
	var less:=PetTable.text("低于","body");less.size_flags_vertical=Control.SIZE_SHRINK_CENTER;picker.add_child(less)
	var below:=SpinBox.new();below.name="CompareThresholdValue";below.min_value=0;below.max_value=100000;below.step=1;below.value=pet_release_below;below.custom_minimum_size=Vector2(100,0)
	below.value_changed.connect(func(value):pet_release_below=int(value));picker.add_child(below)
	var apply:Button=world.button("选择",func():
		if below.get_line_edit().has_focus():below.apply()
		pet_release_below=int(below.value)
		var added:=select_release_below(profile,rows,RELEASE_METRICS[pet_release_metric],pet_release_below)
		feedback="已按条件新增选择 %d 只。"%added;pet_release_confirm=false;rebuild());apply.name="CompareThresholdSelect";apply.tooltip_text="收藏、出战、骑乘的宠物不选";picker.add_child(apply)
	var by_rule:Button=world.button("按保留规则选中",func():select_by_keep_rule(profile);rebuild());by_rule.name="CompareKeepRuleSelect"
	by_rule.tooltip_text="按自动抓极品「属性条件」里这个品种的保留规则，选中规则外的宠物（只选中，确认后才放生）。收藏、出战、骑乘的不选。";picker.add_child(by_rule)

## 保留规则 preview: selects exactly the pets the species' keep rule would
## release and remembers why each other pet stays (shown on its row). Nothing
## is released until the player confirms 放生所选.
func select_by_keep_rule(profile:Dictionary)->void:
	var key:=pet_release_species if not pet_release_species.is_empty() else ""
	if not key.begins_with("original_") or not key.trim_prefix("original_").is_valid_int():
		feedback="这个品种没有原版编号，不能按保留规则选择。";return
	var template:=int(key.trim_prefix("original_"))
	var rule:Dictionary=world.automation_settings().hunt.keep_rule
	var protected:=KeepRule.always_kept(profile)
	protected.merge(KeepRule.capture_helpers(profile,world.automation_settings().get("capture",{})))
	# During a battle its participants stay too (the backend would skip them).
	protected.merge(world.session.battle_pets())
	var verdict:=KeepRule.evaluate(KeepRule.species_pets(profile,template),rule,protected)
	pet_release_selected.clear();pet_release_confirm=false
	for id in verdict.release:pet_release_selected[str(id)]=true
	pet_rule_reasons=verdict.reasons
	var kept:int=verdict.reasons.size()-verdict.release.size()
	feedback="按保留规则：保留 %d 只，选中放生 %d 只。确认前可取消勾选。"%[kept,verdict.release.size()]
	feedback_tooltip="保留规则："+describe_keep_rule(rule)+"。收藏、出战、骑乘和削血宠不选。"

static func describe_keep_rule(rule:Dictionary)->String:
	var stats:Array=rule.get("champion_stats",KeepRule.STATS).map(func(stat):return KeepRule.STAT_NAMES[stat])
	var text:="最高%d档各留%d只，按%s排" % [int(rule.get("tiers",2)),int(rule.get("per_tier",3)),PetStatFilter.describe_order(rule.get("order",["attack","speed","max_hp"]))]
	if int(rule.get("champions",2))>0 and not stats.is_empty():text+="；%s各留前%d" % ["、".join(stats),int(rule.get("champions",2))]
	return text

func select_release_below(profile:Dictionary,rows:Array,metric:String,limit:int)->int:
	var added:=0
	for row in rows:
		var pet:Dictionary=row.pet;var identifier:=str(pet.get("pet_id",""))
		if identifier.is_empty() or pet.get("favorite",false) or pet_release_selected.has(identifier) or not battle_lock(identifier,"放生").is_empty():continue
		if row.location=="pets" and (int(row.index)==int(profile.active_pet) or int(row.index)==int(profile.get("ride_pet",-1))):continue
		if release_metric_value(pet,metric)<limit:pet_release_selected[identifier]=true;added+=1
	return added

func perform_release()->void:
	# A selection made by 按保留规则选中 is logged with the rule's reasons.
	if not pet_rule_reasons.is_empty() and pet_release_species.trim_prefix("original_").is_valid_int():
		world.session.release_source="保留规则";world.session.release_template=int(pet_release_species.trim_prefix("original_"))
	var result:Dictionary=world.release_pets(pet_release_selected.keys())
	if not world.session.last_error.is_empty():feedback=world.session.last_error;pet_release_confirm=false;rebuild();return
	var skipped:Array=result.get("skipped",[])
	feedback="已放生 %d 只"%int(result.released)
	if not skipped.is_empty():feedback+="；跳过 %d 只（%s）"%[skipped.size(),"、".join(skipped.slice(0,4).map(func(item):return "%s %s"%[item.id,item.reason]))+("…" if skipped.size()>4 else "")]
	if not str(result.get("backup","")).is_empty():feedback+="；已备份存档 "+str(result.backup).get_file()
	clear_release_selection();rebuild()

func open_pet_comparison(pet_id:String)->bool:
	if world.area_transition_busy:return false
	var profile:Dictionary=world.session.snapshot()
	for location in ["pets","pet_storage"]:
		for pet in profile.get(location,[]):
			if str(pet.get("pet_id",""))==pet_id:
				pet_compare_subject=pet.duplicate(true);pet_compare_id=pet_id;pet_compare_open=true;world.clear_input();world.paused_input=true;world.classic_hud.map_panel.hide();open_menu("pets");return true
	return false

## Width before the first stat column in 宠物仓库 rows: ★ and the name block.
const STORAGE_LEAD:=204.0 # ★ 26 + name 172 + one separator
const STORAGE_NAME:=172.0

func set_storage_sort(key:String)->void:
	storage_ascending=not storage_ascending if storage_order==key else false
	storage_order=key
	world.set_viewer_pref("storage_order",key)
	world.set_viewer_pref("storage_ascending",storage_ascending)
	pet_storage_page=0
	rebuild()

func pet_storage_panel(profile:Dictionary)->void:
	var storage:Array=profile.get("pet_storage",[])
	var overlay:=pet_overlay("PetStoragePanel","宠物仓库","%d只 · 携带%d/%d" % [storage.size(),profile.pets.size(),world.session.PET_CAPACITY],Vector2(820,mini(650,226+maxi(1,mini(20,storage.size()))*44)))
	overlay_button(overlay,"关闭",752,func():pet_storage_open=false;pet_view="list";rebuild())
	overlay_button(overlay,"宠物记录",656,func():open_pet_records("",-1),"StorageRecords")
	var store_index:=-1
	for i in range(profile.pets.size()):
		if str(profile.pets[i].get("pet_id",""))==pet_storage_target_id:store_index=i
	var store:Button=world.button("存入 "+str(profile.pets[store_index].name) if store_index>=0 else "选中宠物已存入／未选择",func():
		if world.session.store_pet(store_index):world.refresh_companion();world.checkpoint();feedback="已存入仓库。"
		else:feedback=world.session.last_error
		rebuild());store.name="StoreSelectedPet";store.position=Vector2(14,46);store.disabled=store_index<0 or store_index==int(profile.get("ride_pet",-1));overlay.add_child(store)
	var store_lock:=battle_lock(pet_storage_target_id,"存入仓库") if store_index>=0 else ""
	if not store_lock.is_empty():store.disabled=true;store.tooltip_text=store_lock
	load_compare_prefs()
	var sort:=OptionButton.new();sort.name="StorageSort";sort.position=Vector2(250,46);sort.focus_mode=Control.FOCUS_NONE;sort.tooltip_text="仓库排序（这台设备记住）"
	var orders:=PetComparison.STORAGE_KEYS
	for caption in ["现有顺序","最新抓到","最早抓到","等级","三围合","攻击","防御","敏捷","体力"]:sort.add_item(caption)
	sort.select(maxi(0,orders.find(storage_order)))
	sort.item_selected.connect(func(index:int):set_storage_sort(orders[index]))
	overlay.add_child(sort)
	var favorites:=CheckBox.new();favorites.name="StorageFavoritesFirst";favorites.text="收藏优先";favorites.position=Vector2(380,48);favorites.focus_mode=Control.FOCUS_NONE;favorites.tooltip_text="收藏的宠物排在最前面"
	favorites.button_pressed=storage_favorites_first
	favorites.toggled.connect(func(on:bool):storage_favorites_first=on;world.set_viewer_pref("storage_favorites_first",on);rebuild())
	overlay.add_child(favorites)
	var species_names:={}
	for pet in storage:
		var key:=PetComparison.species_key(pet)
		species_names[key]=str(PetComparison.Rules.species_definition(key).get("name",pet.name))
	if not storage_species.is_empty() and not species_names.has(storage_species):storage_species=""
	var species_keys:Array=species_names.keys();species_keys.sort();species_keys.push_front("")
	var picker:=OptionButton.new();picker.name="StorageSpecies";picker.position=Vector2(14,82);picker.size=Vector2(220,28);picker.clip_text=true;picker.focus_mode=Control.FOCUS_NONE
	for key in species_keys:picker.add_item("全部品种" if key=="" else str(species_names[key]))
	picker.select(species_keys.find(storage_species))
	picker.item_selected.connect(func(index:int):storage_species=species_keys[index];world.set_viewer_pref("storage_species",storage_species);pet_storage_page=0;rebuild())
	overlay.add_child(picker)
	var explanation:=PetTable.text("当前属性排序 · 三围合＝攻＋防＋敏 · 再点列名切换升降","meta");explanation.position=Vector2(250,88);overlay.add_child(explanation)
	var rows:=PetComparison.storage_rows(profile,storage_order,storage_favorites_first,storage_ascending,storage_species)
	var count:int=rows.size();var pages:=maxi(1,ceili(count/20.0));pet_storage_page=clampi(pet_storage_page,0,pages-1)
	var previous:Button=world.button("◀",func():pet_storage_page=maxi(0,pet_storage_page-1);rebuild());previous.position=Vector2(620,46);overlay.add_child(previous)
	var page:=PetTable.text("%d / %d 页"%[pet_storage_page+1,pages],"meta");page.position=Vector2(662,52);page.size.x=100;page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;overlay.add_child(page)
	var next:Button=world.button("▶",func():pet_storage_page=mini(pages-1,pet_storage_page+1);rebuild());next.position=Vector2(772,46);overlay.add_child(next)
	var note:=PetTable.text(feedback if not feedback.is_empty() else "出战宠存入时自动撤回；骑乘宠须先下骑。存取保留属性；收藏的排在前面。","meta",PetTable.TEXT if not feedback.is_empty() else null);note.position=Vector2(14,118);overlay.add_child(note)
	var header:=PetTable.header(STORAGE_LEAD,["操作"]);header.position=Vector2(18,142);overlay.add_child(header)
	for i in range(PetTable.COLUMNS.size()):
		var column:Array=PetTable.COLUMNS[i]
		var key:String="stat_total" if column[0]=="sum" else column[0]
		var old:Control=header.get_child(i+1);header.remove_child(old);old.free()
		var button:Button=world.button(str(column[1])+("↑" if storage_ascending else "↓") if storage_order==key else str(column[1]),func():set_storage_sort(key))
		button.name="StorageSort_"+key;button.custom_minimum_size.x=column[2];button.set_meta("compact",true);header.add_child(button);header.move_child(button,i+1)
	var scroll:=ScrollContainer.new();scroll.name="StorageScroll";scroll.position=Vector2(12,170);scroll.size=Vector2(796,maxf(40,overlay.size.y-184));scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",2);scroll.add_child(list)
	# Gold marks the best of each column within the same species.
	var by_species:={}
	for pet in storage:
		var key:=PetComparison.species_key(pet)
		if not by_species.has(key):by_species[key]=[]
		by_species[key].append(pet)
	var best:={}
	for key in by_species:best[key]=PetTable.best_values(by_species[key]) if by_species[key].size()>1 else {}
	var shade:=0
	for entry in rows.slice(pet_storage_page*20,(pet_storage_page+1)*20):
		var index:int=entry.index
		var pet:Dictionary=entry.pet
		var identifier:=str(pet.pet_id)
		var holder:=PetTable.row_panel(shade);shade+=1;holder.name="StorageRow_"+identifier;holder.mouse_filter=Control.MOUSE_FILTER_PASS
		holder.tooltip_text="%s Lv.%d · %s\n攻%d 防%d 敏%d · 三围合%d" % [pet.name,pet.level,pet.get("pet_id","?"),pet.attack,pet.defence,pet.speed,int(pet.attack)+int(pet.defence)+int(pet.speed)]
		list.add_child(holder)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",6);holder.add_child(line)
		add_pet_favorite_button(line,pet,"StorageFavorite_")
		var who:=VBoxContainer.new();who.name="StorageStats_"+identifier;who.custom_minimum_size.x=STORAGE_NAME;who.add_theme_constant_override("separation",-2);line.add_child(who)
		var title:=PetTable.text(str(pet.name),"name");title.clip_text=true;title.custom_minimum_size.x=STORAGE_NAME;who.add_child(title)
		who.add_child(PetTable.text(identifier+(" · GM" if PetComparison.warning(pet) else ""),"meta"))
		PetTable.stat_cells(line,pet,best.get(PetComparison.species_key(pet),{}))
		line.add_child(PetTable.grade(PetComparison.quality(pet)))
		var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",4);actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(actions)
		var retrieve:Button=world.button("取出",func():
			if world.session.retrieve_pet_by_id(identifier):world.refresh_companion();world.checkpoint();feedback="已取出。"
			else:feedback=world.session.last_error
			rebuild());retrieve.name="RetrievePet_"+str(index);retrieve.disabled=profile.pets.size()>=world.session.PET_CAPACITY;retrieve.set_meta("compact",true);actions.add_child(retrieve)
		var compare:Button=world.button("同种比较",func():
			pet_compare_subject=pet.duplicate(true);pet_compare_open=true;rebuild());compare.set_meta("compact",true);actions.add_child(compare)

	style_pet_modal(overlay)

# ---- 宠物记录: 抓到 (抓宠记录) and 放生 (放生记录), server/release_log.gd ------

## Opens 宠物记录 on a tab (caught, released, stops or queue; "" for the
## one last chosen on this device), filtered to one species (template id, -1
## for all). The pet tools, 宠物仓库, 同种比较, 游戏助手 and 自动抓极品 open
## it. 抓到 starts on 本轮 (the current or most recent find-pet run).
const RECORDS_TABS:=["caught","released","stops","queue"]
func open_pet_records(tab:String="",template_id:int=-1)->void:
	if not visible or kind!="pets":open_menu("pets")
	load_records_prefs()
	if tab.is_empty():tab=str(world.viewer_pref("records_tab","caught"))
	records_tab=tab if tab in RECORDS_TABS else "caught"
	records_template=template_id
	records_page=0
	records_run="latest" if records_tab=="caught" else ""
	pet_records_open=true
	fetch_records()

## A tab the player picked is remembered on this device.
func choose_records_tab(tab:String)->void:
	world.set_viewer_pref("records_tab",tab)
	open_pet_records(tab,records_template)

func load_records_prefs()->void:
	if _records_prefs_loaded:return
	_records_prefs_loaded=true
	for tab in records_sorts:
		var saved=world.viewer_pref("records_sort_"+tab,[])
		if saved is Array and saved.size()==2 and str(saved[0]) in ReleaseLog.SORT_KEYS:records_sorts[tab]=[str(saved[0]),bool(saved[1])]
	records_uncaught=bool(world.viewer_pref("records_uncaught",false))

## A stat header was clicked: highest first, again lowest first; key "" goes
## back to the tab's own order. Remembered on this device.
func sort_records(key:String)->void:
	var current:Array=records_sorts.get(records_tab,["",false])
	var ascending:=key==str(current[0]) and not bool(current[1]) and not key.is_empty()
	records_sorts[records_tab]=[key,ascending]
	world.set_viewer_pref("records_sort_"+records_tab,records_sorts[records_tab])
	records_page=0
	if records_tab=="queue":rebuild()
	else:fetch_records()

func set_records_uncaught(on:bool)->void:
	records_uncaught=on
	world.set_viewer_pref("records_uncaught",on)
	records_page=0
	fetch_records()

## 放生记录 directly (kept for callers of the earlier release-only view).
func open_release_log(template_id:int=-1)->void:
	open_pet_records("released",template_id)

## quiet: a live refresh (pet_log_changed, hunt_status_changed) keeps the page
## shown until the new one arrives instead of showing it loading.
func fetch_records(quiet:=false)->void:
	records_loading=not quiet
	_records_fetched_msec=Time.get_ticks_msec()
	var sort:Array=records_sorts.get(records_tab,["",false])
	var asked:=[records_tab,records_page,records_template,records_run,sort.duplicate(),records_uncaught]
	var arrived:=func(data:Dictionary):
		if asked!=[records_tab,records_page,records_template,records_run,records_sorts.get(records_tab,["",false]),records_uncaught]:return
		if quiet and not records_loading and records_data==data:return
		records_data=data
		records_loading=false
		if visible and pet_records_open:rebuild()
	if records_tab=="queue":
		_queue_key=_queue_signature(world.state.automation)
		world.session.hunt_queue(arrived)
	else:
		var options:={"sort":str(sort[0]),"ascending":bool(sort[1]),"uncaught":records_uncaught} if records_tab=="released" else {}
		world.session.pet_log(records_tab,records_page,20,records_template,records_run,arrived,options)
	if records_loading:rebuild()

const RECORDS_REFRESH_MSEC:=500
var _records_fetched_msec:=-100000
var _records_refresh_pending:=false

## Pets were caught or released, or a stop logged (backend pet_log_changed):
## an open 宠物记录 fetches its page again, at most every
## RECORDS_REFRESH_MSEC; rebuild() keeps the scroll place on the same page.
func pet_log_changed()->void:
	if records_tab!="queue":_refresh_records()

## The automation status changed (auto_status): an open 排队 tab fetches the
## queue again when the hit being caught or trained, the battles fought (its
## level) or the queued hits changed.
var _queue_key:=""
func hunt_status_changed(status:Dictionary)->void:
	if records_tab!="queue" or not visible or not pet_records_open:return
	var key:=_queue_signature(status)
	if key==_queue_key:return
	_queue_key=key
	_refresh_records()

static func _queue_signature(status:Dictionary)->String:
	var flow:Dictionary=status.get("flow",{})
	return JSON.stringify([flow.get("phase",""),flow.get("showcase",false),flow.get("current_roll",0),flow.get("queue_limit",0),flow.get("queue",[]).map(func(item):return item.get("roll",0)),status.get("battles",0)])

func _refresh_records()->void:
	if not visible or not pet_records_open or _records_refresh_pending:return
	# Never inside the event itself: the fetch is a backend request.
	var wait:=maxi(0,RECORDS_REFRESH_MSEC-(Time.get_ticks_msec()-_records_fetched_msec))
	_records_refresh_pending=true
	get_tree().create_timer(wait/1000.0).timeout.connect(func():
		_records_refresh_pending=false
		if visible and pet_records_open:fetch_records(true))

const LOG_LEAD:=256.0 # time 66 + name 184 + one separator
const LOG_NAME:=184.0

static func log_time(seconds:int)->String:
	return Time.get_datetime_string_from_unix_time(seconds+local_offset_seconds(),true).substr(5,11)

static func log_place(item:Dictionary)->String:
	var cell:Array=item.get("cell",[])
	var place:=str(item.get("map_name",""))
	if place.is_empty() and int(item.get("map_id",-1))>=0:place="地图%d"%int(item.map_id)
	return place+(" (%d,%d)"%[int(cell[0]),int(cell[1])] if cell.size()==2 else "")

func pet_records_panel()->void:
	var data:=records_data
	var caught:=records_tab=="caught"
	var subtitle:="后台搜宠 · 排队%d只 · 上限%d"%[int(data.get("size",0)),int(data.get("limit",0))] if records_tab=="queue" else "%s共%d条 · 各保留最近%d条"%[{"caught":"抓到","released":"放生","stops":"停止"}.get(records_tab,""),int(data.get("total",0)),ReleaseLog.CAP]
	var overlay:=pet_overlay("PetRecordsPanel","宠物记录",subtitle,Vector2(900,650))
	overlay_button(overlay,"关闭",832,func():pet_records_open=false;rebuild())
	for tab in [["caught","抓到","RecordsTabCaught",566],["released","放生","RecordsTabReleased",626],["stops","停止","RecordsTabStops",686],["queue","排队","RecordsTabQueue",746]]:
		var button:Button=world.button(tab[1],func():
			if records_tab!=tab[0]:choose_records_tab(tab[0]))
		button.name=tab[2];button.position=Vector2(tab[3],10);button.toggle_mode=true;button.button_pressed=records_tab==tab[0];overlay.add_child(button)
		if records_tab==tab[0]:button.add_theme_color_override("font_color",PetTable.GOLD);button.add_theme_color_override("font_pressed_color",PetTable.GOLD)
	if records_tab=="stops":
		stop_records(overlay,data)
		style_pet_modal(overlay)
		return
	if records_tab=="queue":
		queue_records(overlay,data)
		style_pet_modal(overlay)
		return
	var filter:=OptionButton.new();filter.name="RecordsSpecies";filter.position=Vector2(14,46);filter.focus_mode=Control.FOCUS_NONE;filter.custom_minimum_size.x=180
	var choices:=[-1]
	filter.add_item("全部品种")
	for item in data.get("species",[]):
		choices.append(int(item.template_id))
		filter.add_item("%s（%d）"%[item.name,int(item.count)])
	if not choices.has(records_template):
		choices.append(records_template);filter.add_item("原表 %d"%records_template)
	filter.select(choices.find(records_template))
	filter.item_selected.connect(func(index:int):records_template=int(choices[index]);records_page=0;fetch_records())
	overlay.add_child(filter)
	if caught:
		# 本轮: the current or most recent find-pet run; 全部: every capture.
		var run:=OptionButton.new();run.name="RecordsRun";run.position=Vector2(204,46);run.focus_mode=Control.FOCUS_NONE;run.custom_minimum_size.x=150
		var latest:=str(data.get("latest_run",""))
		run.add_item("本轮找宠" if not latest.is_empty() else "本轮找宠（还没有）")
		run.add_item("全部")
		run.select(0 if records_run=="latest" else 1)
		run.item_selected.connect(func(index:int):records_run="latest" if index==0 else "";records_page=0;fetch_records())
		overlay.add_child(run)
	else:
		# Hits the 后台搜宠 queue let go before their capture.
		var uncaught:=CheckBox.new();uncaught.name="RecordsUncaught";uncaught.text="只看未捕获";uncaught.position=Vector2(204,46);uncaught.focus_mode=Control.FOCUS_NONE
		uncaught.tooltip_text="只看后台搜宠排队时放弃、没有抓的（排队已满、门槛已提高），每条写明原因和排在它前面的几只。"
		uncaught.button_pressed=records_uncaught
		uncaught.toggled.connect(set_records_uncaught)
		overlay.add_child(uncaught)
	var pages:=int(data.get("pages",1))
	var previous:Button=world.button("◀",func():records_page=maxi(0,records_page-1);fetch_records());previous.position=Vector2(700,46);previous.disabled=records_page<=0;overlay.add_child(previous)
	var page:=PetTable.text("%d / %d 页"%[records_page+1,pages],"meta");page.position=Vector2(742,52);page.size.x=100;page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;overlay.add_child(page)
	var next:Button=world.button("▶",func():records_page=mini(pages-1,records_page+1);fetch_records());next.position=Vector2(852,46);next.disabled=records_page>=pages-1;overlay.add_child(next)
	var sorted:Array=records_sorts.released
	var hint:="新的在前。数字下的小字是120级推算；红字是后来被放生的。" if caught else ("新的在前" if str(sorted[0]).is_empty() else "按%s%s"%[SORT_NAMES[sorted[0]],"从低到高" if sorted[1] else "从高到低"])+"（未满级按120级推算）。点列名排序，点「时间」回到新的在前。金色：比所有比下它的都高的一项。"
	var note:=PetTable.text("载入中…" if records_loading else hint,"meta");note.position=Vector2(14,84);overlay.add_child(note)
	var header:=PetTable.header(LOG_LEAD,["状态"]) if caught else sort_header("时间",[]);header.position=Vector2(18,108);overlay.add_child(header)
	var scroll:=ScrollContainer.new();scroll.name="RecordsScroll";scroll.position=Vector2(12,130);scroll.size=Vector2(876,506);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",2);scroll.add_child(list)
	var entries:Array=data.get("entries",[])
	if entries.is_empty() and not records_loading:list.add_child(PetTable.text("还没有记录。" if records_run!="latest" else "本轮还没有抓到宠物；选「全部」看以前的。","body"))
	for i in range(entries.size()):
		var item:Dictionary=entries[i]
		var holder:=PetTable.row_panel(i);holder.name=("CaughtRow_%d" if caught else "ReleaseLogRow_%d")%i;holder.mouse_filter=Control.MOUSE_FILTER_PASS
		holder.tooltip_text=caught_description(item) if caught else release_log_description(item)
		list.add_child(holder)
		var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",0);holder.add_child(stack)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",6);stack.add_child(line)
		var when:=PetTable.text(log_time(int(item.get("time",0))),"meta");when.custom_minimum_size.x=66;line.add_child(when)
		var who:=VBoxContainer.new();who.custom_minimum_size.x=LOG_NAME;who.add_theme_constant_override("separation",-2);line.add_child(who)
		var title:=PetTable.text(str(item.get("name","")),"name");title.clip_text=true;title.custom_minimum_size.x=LOG_NAME;who.add_child(title)
		var meta:=PetTable.text("%s · %s"%[item.get("pet_id","?"),item.get("source","")] if caught else "%s · %s · %s"%[item.get("pet_id","?"),item.get("where",""),item.get("source","")],"meta");meta.clip_text=true;meta.custom_minimum_size.x=LOG_NAME;who.add_child(meta)
		if caught:
			var place:=PetTable.text(log_place(item),"meta");place.clip_text=true;place.custom_minimum_size.x=LOG_NAME;place.tooltip_text=place.text;place.mouse_filter=Control.MOUSE_FILTER_PASS;who.add_child(place)
		var judged:Dictionary=item.get("lv120",{})
		var own_best:={}
		var beaten:Array=item.get("beaten_by",[])
		if not caught and not beaten.is_empty():
			# Gold: a stat where it beat every pet that took its place (it still lost).
			for key in ["max_hp","attack","defence","speed"]:
				var mine:=PetTable.value_of(judged if not judged.is_empty() else item,key)
				if beaten.all(func(other):return mine>PetTable.value_of(other,key)):own_best[key]=mine
		PetTable.stat_cells(line,item,own_best,judged)
		var offsets:Array=item.get("offsets",[])
		var total:=0
		for value in offsets:total+=int(value)
		line.add_child(PetTable.grade({} if offsets.size()!=4 else {"offsets":offsets,"total":total,"full":bool(item.get("full",false))}))
		if caught:
			var why:=Button.new();why.name="CaptureReason_%d"%i;why.text=capture_reason_summary(item);why.alignment=HORIZONTAL_ALIGNMENT_LEFT;why.clip_text=true;why.tooltip_text=capture_reason_details(item);stack.add_child(why)
			why.pressed.connect(func():show_capture_reason_details(item))
			var released:Dictionary=item.get("released",{})
			var state:=PetTable.badge("已放生",PetTable.BAD) if not released.is_empty() else PetTable.badge("在",PetTable.GOOD)
			state.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(state)
			if not released.is_empty():
				var gone:=PetTable.text("已放生 %s · %s · %s"%[log_time(int(released.get("time",0))),released.get("source",""),released.get("reason","")],"meta",PetTable.BAD);gone.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;gone.custom_minimum_size.x=840;stack.add_child(gone)
			continue
		var reason:=PetTable.text(str(item.get("reason","")),"body",PetTable.BAD);reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;reason.custom_minimum_size.x=840;stack.add_child(reason)
		if not beaten.is_empty():
			var names:=beaten.map(func(other):return "%s（%d · 攻%d 防%d 敏%d 血%d）"%[other.get("pet_id","?"),int(other.get("sum",0)),int(other.get("attack",0)),int(other.get("defence",0)),int(other.get("speed",0)),int(other.get("max_hp",0))])
			var by:=PetTable.text("被比下去："+"、".join(names),"meta");by.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;by.custom_minimum_size.x=840;stack.add_child(by)
		var origin:Dictionary=item.get("caught",{})
		if not origin.is_empty():
			var from:=PetTable.text("抓到：%s · %s · %s"%[log_time(int(origin.get("time",0))),log_place(origin),origin.get("source","")],"meta");from.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;from.custom_minimum_size.x=840;stack.add_child(from)
	style_pet_modal(overlay)

## A 宠物记录 column header whose stat columns sort the tab (sort_records):
## the active one gold with ▼ (highest first) or ▲. The lead caption (时间,
## 名次) goes back to the tab's own order. Lines up with PetTable.stat_cells
## after LOG_LEAD.
const SORT_NAMES:={"sum":"三围合","attack":"攻击","defence":"防御","speed":"敏捷","max_hp":"血"}
func sort_header(lead_caption:String,after:Array)->HBoxContainer:
	var sort:Array=records_sorts.get(records_tab,["",false])
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",6)
	row.add_child(sort_button(lead_caption,"",66,HORIZONTAL_ALIGNMENT_LEFT,str(sort[0]).is_empty(),false))
	var spacer:=Control.new();spacer.custom_minimum_size=Vector2(LOG_NAME,0);row.add_child(spacer)
	for column in PetTable.COLUMNS:
		if column[0]=="level":
			var level:=PetTable.text(column[1],"head");level.custom_minimum_size=Vector2(column[2],0);level.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;row.add_child(level)
			continue
		row.add_child(sort_button(column[1],column[0],column[2],HORIZONTAL_ALIGNMENT_RIGHT,str(sort[0])==column[0],bool(sort[1])))
	var grade:=PetTable.text("先天","head");grade.custom_minimum_size=Vector2(PetTable.GRADE_WIDTH,0);grade.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;row.add_child(grade)
	for caption in after:row.add_child(PetTable.text(caption,"head"))
	return row

func sort_button(caption:String,key:String,width:float,align:int,active:bool,ascending:bool)->Button:
	var button:=Button.new();button.name="RecordsSort_"+(key if not key.is_empty() else "own")
	button.text=caption+(("▲" if ascending else "▼") if active and not key.is_empty() else "")
	button.flat=true;button.focus_mode=Control.FOCUS_NONE;button.alignment=align;button.custom_minimum_size=Vector2(width,0)
	button.clip_text=false;button.set_meta("sort_header",true)
	button.tooltip_text="按%s排序（再点一次反过来）"%SORT_NAMES[key] if not key.is_empty() else "回到原来的顺序"
	for state in ["normal","hover","pressed","focus","disabled"]:button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	button.add_theme_font_override("font",PetTable.font(600))
	button.add_theme_font_size_override("font_size",12)
	var color:=PetTable.GOLD if active else PetTable.MUTED
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(state,color)
	button.add_theme_color_override("font_hover_color",PetTable.BRIGHT)
	button.pressed.connect(sort_records.bind(key))
	return button

## 排队: the 后台搜宠 queue (automation.gd queue_view, backend hunt_queue):
## the hit being caught or trained on top (当前, outside the ranking), then
## every queued hit with its rank, roll, Lv, 成长档 and predicted Lv.120
## stats; sorted by a stat column on request.
const QUEUE_PHASES:={"capture":"捕获中","train":"练级中","restart":"刚练完"}
func queue_records(overlay:Control,data:Dictionary)->void:
	var sort:Array=records_sorts.queue
	var hint:="每个品种各自排队，各自最多%d只；名次按这个品种保留规则的排序，排满后放弃这个品种最后一只（记入放生「未捕获」）。轮流抓：每次抓下一个品种排第一的。数字是预测的120级属性；点列名在每个品种里排序，点「名次」回到排队顺序。"%int(data.get("limit",0))
	var note:=PetTable.text("载入中…" if records_loading else hint,"meta");note.position=Vector2(14,46);note.custom_minimum_size=Vector2(870,0);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;overlay.add_child(note)
	var header:=sort_header("名次",["状态"]);header.position=Vector2(18,108);overlay.add_child(header)
	var scroll:=ScrollContainer.new();scroll.name="RecordsScroll";scroll.position=Vector2(12,130);scroll.size=Vector2(876,506);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",2);scroll.add_child(list)
	var rows:=sorted_queue(data.get("entries",[]),data.get("groups",[]),str(sort[0]),bool(sort[1]))
	if rows.is_empty() and not records_loading:
		var empty:="没有在进行的后台搜宠。在自动抓极品里开始找宠流程（开着后台搜宠）后，这里显示正在抓或练的这只和排队的宠物。"
		if bool(data.get("active",false)):empty="排队是空的：后台正在继续找。"
		elif str(data.get("phase","idle")) in ["hunt","reveal","capture","train","restart"] and not bool(data.get("showcase",false)):empty="这一轮没开后台搜宠：找到就直接抓，不排队。"
		var label:=PetTable.text(empty,"body");label.name="QueueEmpty";label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=840;list.add_child(label)
	# Gold marks the best of each species: stats of different species do not compare.
	var best_of:={}
	for id in rows.filter(func(row):return not row.has("group")).map(func(row):return int(row.get("template_id",-1))):
		if not best_of.has(id):best_of[id]=PetTable.best_values(rows.filter(func(row):return not row.has("group") and int(row.get("template_id",-1))==id))
	var index:=0
	for item in rows:
		if item.has("group"):
			var group:Dictionary=item.group
			var title_row:=HBoxContainer.new();title_row.name="QueueGroup_%d"%int(group.get("template_id",-1));title_row.add_theme_constant_override("separation",10)
			title_row.add_child(PetTable.text(str(group.get("name","")),"section"))
			var count:=PetTable.text("排队 %d / %d"%[int(group.get("count",0)),int(data.get("limit",0))],"meta",PetTable.BAD if int(group.get("count",0))>=int(data.get("limit",0)) else null);count.size_flags_vertical=Control.SIZE_SHRINK_END;title_row.add_child(count)
			list.add_child(title_row)
			continue
		var current:=bool(item.get("current",false))
		var holder:=PetTable.row_panel(index,current);holder.name="QueueRow_%d"%index;holder.mouse_filter=Control.MOUSE_FILTER_PASS
		index+=1
		holder.tooltip_text=queue_description(item)
		list.add_child(holder)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",6);holder.add_child(line)
		var rank_box:=CenterContainer.new();rank_box.custom_minimum_size.x=66;line.add_child(rank_box)
		rank_box.add_child(PetTable.badge("当前",PetTable.GOLD) if current else PetTable.text("第%d名"%int(item.get("rank",0)),"body"))
		var who:=VBoxContainer.new();who.custom_minimum_size.x=LOG_NAME;who.add_theme_constant_override("separation",-2);line.add_child(who)
		var title:=PetTable.text(str(item.get("name","")),"name");title.clip_text=true;title.custom_minimum_size.x=LOG_NAME;who.add_child(title)
		var meta:=PetTable.text("第%d组"%int(item.get("roll",0))+(" · "+str(item.pet_id) if not str(item.get("pet_id","")).is_empty() else ""),"meta");meta.clip_text=true;meta.custom_minimum_size.x=LOG_NAME;who.add_child(meta)
		PetTable.stat_cells(line,item,{} if current else best_of.get(int(item.get("template_id",-1)),{}))
		var offsets:Array=item.get("offsets",[])
		line.add_child(PetTable.grade({} if offsets.size()!=4 else {"offsets":offsets,"total":int(item.get("total_offset",0)),"full":bool(item.get("full",false))}))
		if current:
			var phase:=PetTable.badge(str(QUEUE_PHASES.get(str(item.get("phase","")),"处理中")),PetTable.GOOD);phase.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(phase)
		if bool(item.get("survey",false)):
			var survey:=PetTable.badge("摸底",PetTable.GOLD);survey.size_flags_vertical=Control.SIZE_SHRINK_CENTER;survey.tooltip_text="摸底选中：没有门槛时从候选里按保留规则挑出的，一定会抓。";line.add_child(survey)

## The 排队 rows in display order: the current hit first, then each species'
## queue under a {group} header (groups: the backend's order), in its rank or
## by a stat within the species (ties keep the rank).
static func sorted_queue(entries:Array,groups:Array,key:String,ascending:bool)->Array:
	var result:=entries.filter(func(item):return bool(item.get("current",false)))
	for group in groups:
		var queued:=entries.filter(func(item):return not bool(item.get("current",false)) and int(item.get("template_id",-1))==int(group.get("template_id",-1)))
		if queued.is_empty():continue
		if key in ReleaseLog.SORT_KEYS:
			queued.sort_custom(func(a,b):
				var va:=PetTable.value_of(a,key)
				var vb:=PetTable.value_of(b,key)
				if va!=vb:return va<vb if ascending else va>vb
				return int(a.get("rank",0))<int(b.get("rank",0)))
		result.append({"group":group})
		result.append_array(queued)
	return result

static func queue_description(item:Dictionary)->String:
	var offsets:Array=item.get("offsets",[])
	var place:="当前 · %s"%QUEUE_PHASES.get(str(item.get("phase","")),"处理中") if bool(item.get("current",false)) else "本品种排队第%d名"%int(item.get("rank",0))
	return "%s 第%d组 · Lv.%d · %s%s\n预测120级 血%d 攻%d 防%d 敏%d · 三围合%d\n成长档 %s"%[item.get("name",""),int(item.get("roll",0)),int(item.get("level",1)),place," · 摸底选中" if bool(item.get("survey",false)) else "",
		int(item.get("max_hp",0)),int(item.get("attack",0)),int(item.get("defence",0)),int(item.get("speed",0)),int(item.get("sum",0)),"未知" if offsets.size()!=4 else "%s 总%+d"%[str(offsets),int(item.get("total_offset",0))]]

## 停止记录: why 自动抓极品 or the find-pet cycle stopped, paused, skipped a
## hit or finished (automation.gd _record_stop), newest first.
const STOP_COLORS:={"停止":PetTable.BAD,"暂停":PetTable.GOLD,"已跳过":PetTable.MUTED,"已重试":PetTable.MUTED,"已恢复":PetTable.GOOD,"完成":PetTable.GOOD,"找到":PetTable.GOOD}
func stop_records(overlay:Control,data:Dictionary)->void:
	var pages:=int(data.get("pages",1))
	var previous:Button=world.button("◀",func():records_page=maxi(0,records_page-1);fetch_records());previous.position=Vector2(700,46);previous.disabled=records_page<=0;overlay.add_child(previous)
	var page:=PetTable.text("%d / %d 页"%[records_page+1,pages],"meta");page.position=Vector2(742,52);page.size.x=100;page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;overlay.add_child(page)
	var next:Button=world.button("▶",func():records_page=mini(pages-1,records_page+1);fetch_records());next.position=Vector2(852,46);next.disabled=records_page>=pages-1;overlay.add_child(next)
	var hint:="新的在前。停止：要你处理；暂停：换了地图、战败或服务器重启；已恢复：服务器重启后自动接着运行；已跳过、已重试：流程自己继续了；完成：收集够了或停下比较。"
	var note:=PetTable.text("载入中…" if records_loading else hint,"meta");note.position=Vector2(14,46);note.custom_minimum_size=Vector2(670,0);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;overlay.add_child(note)
	var scroll:=ScrollContainer.new();scroll.name="RecordsScroll";scroll.position=Vector2(12,96);scroll.size=Vector2(876,540);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",2);scroll.add_child(list)
	var entries:Array=data.get("entries",[])
	if entries.is_empty() and not records_loading:list.add_child(PetTable.text("还没有记录。自动抓极品每次停下、暂停或跳过一只都会记在这里。","body"))
	for i in range(entries.size()):
		var item:Dictionary=entries[i]
		var holder:=PetTable.row_panel(i);holder.name="StopRow_%d"%i;holder.mouse_filter=Control.MOUSE_FILTER_PASS
		holder.tooltip_text=stop_description(item)
		list.add_child(holder)
		var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",0);holder.add_child(stack)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",8);stack.add_child(line)
		var when:=PetTable.text(log_time(int(item.get("time",0))),"meta");when.custom_minimum_size.x=66;line.add_child(when)
		var outcome:=str(item.get("outcome",""))
		var state:=PetTable.badge(outcome,STOP_COLORS.get(outcome,PetTable.MUTED));state.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(state)
		var reason:=PetTable.text(str(item.get("reason","")).replace("\n"," "),"body",PetTable.BAD if outcome=="停止" else PetTable.TEXT);reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;reason.custom_minimum_size.x=720;line.add_child(reason)
		var details:=PetTable.text(stop_details(item),"meta");details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=840;stack.add_child(details)

const STOP_PHASES:={"hunt":"筛选中","reveal":"亮出预测","capture":"捕捉中","train":"练级中","restart":"准备下一只","compare":"比较","paused":"已暂停","idle":""}
static func stop_details(item:Dictionary)->String:
	var parts:=["找宠流程" if str(item.get("scope",""))=="flow" else "自动抓极品"]
	var phase:=str(STOP_PHASES.get(str(item.get("phase","")),item.get("phase","")))
	if not phase.is_empty():parts.append(phase)
	if not str(item.get("name","")).is_empty():parts.append(str(item.name)+(" "+str(item.pet_id) if not str(item.get("pet_id","")).is_empty() else ""))
	parts.append("已遇敌 %d 组"%int(item.get("rolls",0)))
	if str(item.get("scope",""))=="flow":parts.append("达标 %d · 存仓 %d · 跳过 %d · 放生 %d"%[int(item.get("collected",0)),int(item.get("stored",0)),int(item.get("skipped",0)),int(item.get("released",0))])
	var place:=log_place(item)
	if not place.strip_edges().is_empty():parts.append(place)
	return " · ".join(parts)

static func stop_description(item:Dictionary)->String:
	return "%s %s\n%s\n%s"%[log_time(int(item.get("time",0))),item.get("outcome",""),str(item.get("reason","")),stop_details(item)]

static func caught_description(item:Dictionary)->String:
	var text:="%s %s · Lv.%d · %s · %s\n血%d 攻%d 防%d 敏%d · 三围合%d" % [item.get("name",""),item.get("pet_id","?"),int(item.get("level",1)),log_place(item),item.get("source",""),int(item.get("max_hp",0)),int(item.get("attack",0)),int(item.get("defence",0)),int(item.get("speed",0)),int(item.get("sum",0))]
	var judged:Dictionary=item.get("lv120",{})
	if not judged.is_empty():text+="\n120级 血%d 攻%d 防%d 敏%d · 三围合%d"%[int(judged.max_hp),int(judged.attack),int(judged.defence),int(judged.speed),int(judged.attack)+int(judged.defence)+int(judged.speed)]
	var released:Dictionary=item.get("released",{})
	if not released.is_empty():text+="\n已放生：%s"%released.get("reason","")
	text+="\n"+capture_reason_details(item)
	return text

static func release_log_description(item:Dictionary)->String:
	var text:="%s %s · Lv.%d · %s · %s\n血%d 攻%d 防%d 敏%d · 三围合%d\n%s" % [item.get("name",""),item.get("pet_id","?"),int(item.get("level",1)),item.get("where",""),item.get("source",""),int(item.get("max_hp",0)),int(item.get("attack",0)),int(item.get("defence",0)),int(item.get("speed",0)),int(item.get("sum",0)),item.get("reason","")]
	var beaten:Array=item.get("beaten_by",[])
	if not beaten.is_empty():text+="\n被比下去："+"、".join(beaten.map(func(other):return str(other.get("pet_id","?"))))
	var origin:Dictionary=item.get("caught",{})
	if not origin.is_empty():text+="\n抓到：%s"%log_place(origin)
	return text

## The local timezone offset for log times (the logs store UTC seconds).
static func local_offset_seconds()->int:
	return int(Time.get_time_zone_from_system().get("bias",0))*60

func continue_comparison_hunt(selected:Dictionary)->bool:
	var key:=PetComparison.species_key(selected)
	var ident:=int(key.trim_prefix("original_")) if key.begins_with("original_") else -1
	var options:Array=preload("res://scripts/pet_hunt_rules.gd").candidates(world.encounter_catalog,int(world.data.map_id),world.cell,world.pet_hunt_menu.level_one.button_pressed)
	if ident<0 or not options.any(func(row):return int(row.id)==ident):
		feedback="当前位置不能刷选中的同种宠物；请先到对应遇敌区域。";rebuild();return false
	world.close_adventure_menu();world.pet_hunt_menu.open_menu()
	var index:int=world.pet_hunt_menu.species.get_item_index(ident)
	if index<0 or world.pet_hunt_menu.species.is_item_disabled(index):
		world.pet_hunt_menu.close_menu();world.paused_input=true;open_menu("pets");feedback="选中宠物素材不可用。";rebuild();return false
	world.pet_hunt_menu.species.select(index)
	return true

func add_pet_favorite_button(parent:Control,pet:Dictionary,prefix:String)->void:
	var identifier:=str(pet.get("pet_id",""))
	var favorite:=bool(pet.get("favorite",false))
	var toggle:Button=world.button("★" if favorite else "☆",func():
		if world.session.set_pet_favorite(identifier,not favorite):world.checkpoint();feedback="已取消收藏。" if favorite else "已收藏；仓库内优先显示。"
		else:feedback=world.session.last_error
		rebuild())
	toggle.name=prefix+identifier
	toggle.tooltip_text="取消收藏" if favorite else "收藏（收藏的不会被放生）"
	toggle.set_meta("compact",true)
	toggle.custom_minimum_size=Vector2(26,0)
	if favorite:toggle.modulate=Color("ffe680")
	parent.add_child(toggle)

static func capture_reason_summary(item:Dictionary)->String:
	var decision:Dictionary=item.get("capture_decision",{})
	var names:={"capture_only":"只抓不练","stats":"属性达标","survey":"摸底挑选","unconditional":"未设条件，每只都抓","mixed_if_stats":"混合遇敌例外","manual":"手动捕获","gm":"GM发放","automatic":"自动抓宠"}
	var tags:Array=decision.get("tags",[])
	var destination := str(decision.get("destination_text",""))
	return "为什么抓："+(" · ".join(tags.map(func(tag):return names.get(tag,str(tag)))) if not tags.is_empty() else "—")+(" · "+destination if not destination.is_empty() else "")+" · 点开详情"

static func capture_reason_details(item:Dictionary)->String:
	var decision:Dictionary=item.get("capture_decision",{})
	if decision.is_empty():return "为什么抓：—（旧记录未保存捕获原因）"
	var lines:Array=[capture_reason_summary(item).trim_suffix(" · 点开详情"),"捕获加入背包前冻结；预测120级，同种随身、仓库和等待队列比较"]
	var threshold:=str(decision.get("threshold_text",""))
	if not threshold.is_empty():lines.append(threshold)
	for metric in decision.get("metrics",[]):
		lines.append("%s %d · %s第%d · 原最高 %s"%[PetStatFilter.RANK_NAMES.get(str(metric.key),str(metric.key)),int(metric.value),"并列" if int(metric.get("ties",0))>0 else "",int(metric.rank),str(metric.original_max) if metric.get("original_max")!=null else "—"])
	var queued:Dictionary=decision.get("queue",{})
	if not queued.is_empty():lines.append("本种排队：入选时第%s · 出队时第%s · 等待%s秒（入选至出队）"%[str(queued.admission_rank) if queued.get("admission_rank")!=null else "—",str(queued.departure_rank) if queued.get("departure_rank")!=null else "—",str(snappedf(float(queued.wait_seconds),0.1)) if queued.has("wait_seconds") else "—"])
	return "\n".join(lines)

## In the game's scaled canvas, so portrait devices use the same touch flow.
func show_capture_reason_details(item:Dictionary)->void:
	var previous:=panel.get_node_or_null("CaptureReasonDetails")
	if previous!=null:previous.free()
	var details:=pet_overlay("CaptureReasonDetails","为什么抓这只",str(item.get("name","")),Vector2(900,650))
	details.z_index=20
	overlay_button(details,"关闭",832,details.queue_free,"CaptureReasonClose")
	var scroll:=ScrollContainer.new();scroll.position=Vector2(18,55);scroll.size=Vector2(864,570);details.add_child(scroll)
	var text:=PetTable.text(capture_reason_details(item),"body");text.name="CaptureReasonText";text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=840;scroll.add_child(text)
