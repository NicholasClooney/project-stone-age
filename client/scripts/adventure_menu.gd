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
var pet_compare_sort := "stat_total"
var pet_compare_projected := false
# 放生 selection for the comparison overlay: stable pet_id -> true, per species.
var pet_release_selected: Dictionary = {}
var pet_release_species := ""
var pet_release_confirm := false
var pet_release_metric := 0
var pet_release_below := 620
const RELEASE_METRICS := ["stat_total","attack","defence","speed"]
const PetComparison=preload("res://scripts/pet_comparison.gd")
const PetGrowth = preload("res://scripts/pet_growth.gd")
const AnimatedPortrait = preload("res://scripts/animated_portrait.gd")
const Riding = preload("res://scripts/riding.gd")
## Facing of the pet window's portrait; the original starts at 1 each time it opens.
var pet_portrait_facing := 1
var name_edit: LineEdit
var art: Dictionary = {}
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
	pet_rename = false
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
	var view := [kind,pet_view,pet_category,pet_page,pet_compare_open,pet_compare_page,pet_storage_open,pet_storage_page]
	var before: Array[Vector2i] = world.capture_scroll(self) if view==_built_view else ([] as Array[Vector2i])
	_rebuild_panel()
	_built_view = view
	world.restore_scroll(self,before)

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
	if kind in ["quest","system"]:
		stone(Rect2(0,0,704,432))
		label("村外的伙伴" if kind=="quest" else "系统",Vector2(24,16),600,21)
	match kind:
		"status":
			status_panel(profile)
		"inventory":
			inventory_panel(profile)
		"pets":
			if pet_compare_open and not pet_compare_subject.is_empty():pet_comparison_panel(profile,pet_compare_subject)
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
		"system":
			label("旅程会自动保存。\n继续探索，进度不会丢失。" if world.profile_persistence else "临时旅程：存档未启用。",Vector2(30,78),360,18)
			choice("保存旅程",Vector2(420,90),"save",null,world.profile_persistence and not world.battle_view.visible)
			choice("音乐开关",Vector2(420,145),"mute")
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
	elif kind in ["status","pets","system"]:
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
	var frames: Array = AnimatedPortrait.manifest().characters[str(sprite)]["3_0"].frames
	var view := TextureRect.new()
	view.texture = load("res://assets/legacy/battle/images/%d.png" % int(frames[0].image))
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
	portrait(int(profile.get("character_id","100000")),Vector2(177,84),Vector2(64,68))
	var values := [str(p.level),str(p.xp),str(int(p.level)*30-int(p.xp)),"%d / %d" % [p.hp,p.max_hp],"—",str(effective.attack),str(effective.defence),str(effective.speed),"—"]
	for i in range(values.size()):label(values[i],Vector2(87,70+i*21),83,13)
	var base_positions := [Vector2(81,288),Vector2(201,288),Vector2(81,308),Vector2(201,308)]
	var base_keys := ["vitality","strength","toughness","dexterity"]
	for i in range(base_keys.size()):label(str(int(int(p.base_stats[base_keys[i]])/100)),base_positions[i],28,13)
	label("石币 %d" % p.gold,Vector2(18,331),248,13)
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

func item_name(key: String) -> String:
	return {"potion":"耐久力回复药","club":"小棍棒","healing_charm":"恢复护符（辅助）","mirror_charm":"美丽尼亚护身符1"}.get(key,key)

func item_description(key: String) -> String:
	return {"potion":"恢复体力；战斗中也可使用。","club":"攻击 +4；装备后生效。","healing_charm":"恢复存活随身宠；自动战斗半血治疗，不耗气。","mirror_charm":"主动镜之精灵：消耗行动，暂不消耗气力。"}.get(key,"")

func item_equipped(profile: Dictionary, key: String) -> bool:
	return bool(profile.get("equipped",false)) if key=="club" else bool(profile.get("equipped_mirror",false)) if key=="mirror_charm" else false

func equip_action(key: String) -> String:
	return "heal_pets" if key=="healing_charm" else "equip_mirror" if key=="mirror_charm" else "equip"

func inventory_panel(profile: Dictionary) -> void:
	image(26060,Vector2.ZERO)
	image(26061,Vector2(0,159))
	label(str(profile.player.gold),Vector2(182,84),75,14)
	# Classic five-slot frame: InitItem menu.cpp8940-8973. Weapon is
	# CHAR_ARM=2 at(61,129), not the top-left accessory slot. The frame
	# already contains head/body/hand silhouettes; no invented mannequin.
	for key in ["club","mirror_charm"]:
		if not item_equipped(profile,key):continue
		var center:=Vector2(61,129) if key=="club" else Vector2(32,68)
		var icon:=item_icon(key,Vector2.ZERO)
		icon.position=Vector2(49,118) if key=="club" else center-icon.texture.get_size()/2
		icon.name="EquippedClubIcon" if key=="club" else "EquippedMirrorIcon"
		var equipped_slot := choice("",center-Vector2(23,23),"",null)
		for connection in equipped_slot.pressed.get_connections():equipped_slot.pressed.disconnect(connection.callable)
		equipped_slot.name="EquippedClub" if key=="club" else "EquippedMirror"
		equipped_slot.size=Vector2(48,48)
		equipped_slot.tooltip_text=item_name(key)+" · 双击卸下"
		var selection:="equipped" if key=="club" else "equipped_mirror"
		Highlight.attach(equipped_slot,Rect2(Vector2(-1,-1),Vector2(50,47)),selected_item_slot==selection)
		equipped_slot.pressed.connect(func(): selected_item=key;selected_item_slot=selection;rebuild())
		equipped_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				world.perform_adventure_action(equip_action(key),false)
		)
	for i in range(4):
		var key: String = ["potion","club","mirror_charm","healing_charm"][i]
		# Authority inventory is total owned; equipment consumes one visible
		# bag copy without deleting ownership. Spare copies remain in the bag.
		var bag_count := maxi(0,int(profile.inventory.get(key,0))-(1 if item_equipped(profile,key) else 0))
		if bag_count>0:
			var offset := Vector2(-11,-21) if key=="potion" else Vector2(-12,-11)
			item_icon(key,Vector2(32+i*51,200)+offset).name="BagIcon_"+key
			label(str(bag_count),Vector2(31+i*51,201),40,12).name="BagCount_"+key
		var slot := choice("",Vector2(11+i*51,175),"",null,bag_count>0)
		for connection in slot.pressed.get_connections():slot.pressed.disconnect(connection.callable)
		slot.name="ItemSlot_"+key
		slot.size=Vector2(48,48)
		slot.tooltip_text=item_name(key)+( "" if key=="potion" else " · 双击装备")
		Highlight.attach(slot,Rect2(Vector2(-3,1),Vector2(50,47)),selected_item_slot==key and bag_count>0)
		slot.pressed.connect(func(): selected_item=key;selected_item_slot=key;rebuild())
		slot.gui_input.connect(func(event: InputEvent):
			if key!="potion" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				if not item_equipped(world.session.snapshot(),key):world.perform_adventure_action(equip_action(key),true)
		)
	var potion := selected_item=="potion"
	label(item_name(selected_item),Vector2(15,328),240,15)
	label(item_description(selected_item),Vector2(15,354),239,14)
	choice("使用" if potion else ("恢复宠物" if selected_item=="healing_charm" else "卸下" if item_equipped(profile,selected_item) else "装备"),Vector2(14,404),"use_potion" if potion else equip_action(selected_item),null if potion else not item_equipped(profile,selected_item),int(profile.inventory.get(selected_item,0))>0 and (not potion or int(profile.player.hp)<int(profile.player.max_hp)))

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
	pet_native_button(26043,Vector2(190,317),func(): pet_switch_view("list"))
	pet_navigation(pets.size(),317)
	if pet_rename:pet_rename_panel(pet)

func pet_navigation(_count: int, y: float) -> void:
	var indices := filtered_pet_indices(world.session.snapshot())
	if indices.is_empty():return
	var position := maxi(0,indices.find(selected_pet))
	pet_native_button(26180,Vector2(60,y),func(): selected_pet=int(indices[(position+indices.size()-1)%indices.size()]); rebuild(),"上一只")
	pet_native_button(26182,Vector2(104,y),func(): selected_pet=int(indices[(position+1)%indices.size()]); rebuild(),"下一只")

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
	stone(Rect2(origin,Vector2(256,432)))
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
	label(feedback,origin+Vector2(16,370),230,12)
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
	for i in range(3):
		var key: String = ["potion","club","mirror_charm"][i]
		var caption := item_name(key)
		item_icon(key,Vector2(25,119+i*64))
		label(caption,Vector2(85,117+i*64),190,16)
		label("%d 石币    持有 %d" % [[10,30,4800][i],profile.inventory.get(key,0)],Vector2(85,141+i*64),230,14)
		var row:=choice("",Vector2(18,111+i*64),"",null)
		for connection in row.pressed.get_connections():row.pressed.disconnect(connection.callable)
		row.size=Vector2(390,58)
		row.pressed.connect(func(): selected_item=key;rebuild())
	item_icon(selected_item,Vector2(43,319))
	label(item_name(selected_item)+(" · 镜之精灵" if selected_item=="mirror_charm" else " · "+item_description(selected_item)),Vector2(111,310),300,13)
	label("售出 %d 石币" % ({"potion":5,"club":15,"mirror_charm":2400}[selected_item]),Vector2(111,338),200,14)
	art_button(26098,Vector2(231,382),"buy_"+selected_item,null,int(profile.player.gold)>=({"potion":10,"club":30,"mirror_charm":4800}[selected_item])).tooltip_text="购买一个"
	art_button(26097,Vector2(312,382),"sell_"+selected_item,null,int(profile.inventory.get(selected_item,0))>0 and (not item_equipped(profile,selected_item) or int(profile.inventory.get(selected_item,0))>1)).tooltip_text="卖出一个"

func style_pet_modal(root_control:Control)->void:
	if readable_font==null:
		readable_font=FontVariation.new();readable_font.base_font=load("res://assets/fonts/NotoSansSC.ttf");readable_font.variation_opentype={2003265652:600.0}
	root_control.add_theme_font_override("font",readable_font)
	for node in root_control.find_children("*","Control",true,false):node.add_theme_font_override("font",readable_font)

func pet_comparison_panel(profile:Dictionary,selected:Dictionary)->void:
	var overlay:=Panel.new();overlay.name="PetComparisonPanel";overlay.position=Vector2.ZERO;overlay.z_index=10;overlay.mouse_filter=Control.MOUSE_FILTER_STOP;overlay.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"));overlay.size=Vector2(760,610);overlay.add_theme_stylebox_override("panel",world.box(Color("182324"),Color("b8a47c")));panel.add_child(overlay)
	var title:Label=world.text("同种比较 · "+str(selected.name)+" · 携带与仓库",18);title.position=Vector2(14,12);overlay.add_child(title)
	var close:Button=world.button("关闭",func():pet_compare_open=false;pet_view="list";clear_release_selection();rebuild());close.position=Vector2(650,8);overlay.add_child(close)
	if PetComparison.species_key(selected)!=pet_release_species:
		clear_release_selection();pet_release_species=PetComparison.species_key(selected)
	var hunt:Button=world.button("自动抓极品",func():continue_comparison_hunt(selected));hunt.position=Vector2(490,8);hunt.name="CompareContinueHunt";overlay.add_child(hunt)
	var sort:=OptionButton.new();sort.name="PetCompareSort";sort.position=Vector2(14,48)
	var keys:=["stat_total","max_hp","attack","defence","speed"]
	for caption in ["三围合降序","体力降序","攻击降序","防御降序","敏捷降序"]:sort.add_item(caption)
	sort.select(keys.find(pet_compare_sort));sort.item_selected.connect(func(i):pet_compare_sort=keys[i];rebuild());overlay.add_child(sort)
	var predicted:=CheckButton.new();predicted.text="按120级属性排序";predicted.position=Vector2(180,45);predicted.button_pressed=pet_compare_projected;predicted.toggled.connect(func(on):pet_compare_projected=on;rebuild());overlay.add_child(predicted)
	var filter_result_height:=0
	var info:Label=world.text(feedback if not feedback.is_empty() else "未满级宠物按成长种子精确推算120级属性，可跨等级比较。",12);info.name="PetComparisonInfo";info.position=Vector2(14,89);overlay.add_child(info)
	var scroll:=ScrollContainer.new();scroll.position=Vector2(12,196);scroll.size=Vector2(736,396);overlay.add_child(scroll)
	if is_instance_valid(world.pet_workflow) and world.pet_workflow.phase=="compare" and world.pet_workflow.pet_id==str(selected.get("pet_id","")):
		info.text=world.pet_workflow.reason;info.tooltip_text=info.text;info.clip_text=true;info.size=Vector2(730,60);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		filter_result_height=44;scroll.position.y+=44;scroll.size.y-=44
	scroll.size.y-=88
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var rows:=PetComparison.rows(profile,selected,pet_compare_sort,pet_compare_projected)
	release_controls(overlay,profile,rows,scroll.position.y+scroll.size.y+6)
	var focus_id:=str(selected.get("pet_id",""))
	var focus:Dictionary=selected
	for row in rows:
		if str(row.pet.get("pet_id",""))==focus_id:focus=row.pet
	var leader:Dictionary=rows[0].pet if not rows.is_empty() else focus
	for entry in [["选中",focus,108],["当前分组首位",leader,150]]:
		var actor:Dictionary=entry[1]
		var summary:Label=world.text("%s %s · %s Lv.%d\n当前 血%d 攻%d 防%d 敏%d · 三围合%d" % [entry[0],actor.get("pet_id","?"),actor.name,actor.level,actor.max_hp,actor.attack,actor.defence,actor.speed,int(actor.attack)+int(actor.defence)+int(actor.speed)],13)
		summary.position=Vector2(14,int(entry[2])+filter_result_height);summary.name="ComparePinned_"+str(entry[0]);overlay.add_child(summary)
	var pages:=maxi(1,ceili(rows.size()/20.0));pet_compare_page=clampi(pet_compare_page,0,pages-1)
	var previous:Button=world.button("◀",func():pet_compare_page=maxi(0,pet_compare_page-1);rebuild());previous.position=Vector2(470,46);overlay.add_child(previous)
	var next:Button=world.button("▶",func():pet_compare_page=mini(pages-1,pet_compare_page+1);rebuild());next.position=Vector2(640,46);overlay.add_child(next)
	var page:Label=world.text("%d/%d · %d只"%[pet_compare_page+1,pages,rows.size()],13);page.position=Vector2(530,53);overlay.add_child(page)
	var last_group:=""
	for row in rows.slice(pet_compare_page*20,(pet_compare_page+1)*20):
		if str(row.location)!=last_group:
			last_group=str(row.location)
			var heading:Label=world.text("随身宠物" if last_group=="pets" else "仓库宠物",16);heading.name="CompareGroup_"+last_group;list.add_child(heading)
		var pet:Dictionary=row.pet;var estimate:Dictionary=row.forecast.get("expected",pet);var q:Dictionary=row.quality
		var identifier:=str(pet.get("pet_id",str(row.location)+"#"+str(row.index+1)))
		var stats_line:="当前 血%d 攻%d 防%d 敏%d · 三围合%d" % [pet.max_hp,pet.attack,pet.defence,pet.speed,int(pet.attack)+int(pet.defence)+int(pet.speed)]
		if int(pet.level)<120:stats_line+="\n120级 血%d 攻%d 防%d 敏%d · 三围合%d" % [estimate.max_hp,estimate.attack,estimate.defence,estimate.speed,int(estimate.attack)+int(estimate.defence)+int(estimate.speed)]
		var content:="%s · Lv.%d · %s · ID %s\n%s\n先天 %s%s" % [pet.name,pet.level,"携带" if row.location=="pets" else "仓库",identifier,stats_line,"未知" if q.is_empty() else str(q.offsets)+" 总%+d"%q.total+(" 满档" if q.full else "")," · GM／旧档，不作天然品质判断" if PetComparison.warning(pet) else ""]
		var text:Label=world.text(content,13);text.name="CompareRow_"+str(row.location)+"_"+str(row.index);text.custom_minimum_size=Vector2(700,100 if int(pet.level)<120 else 85);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if identifier==focus_id:text.modulate=Color("ffe680");text.text="▶ 当前选中 · "+text.text
		list.add_child(text)
		var actions:=HBoxContainer.new();list.add_child(actions)
		var pick:=CheckBox.new();pick.name="CompareSelect_"+identifier;pick.text="选";pick.focus_mode=Control.FOCUS_NONE;pick.button_pressed=pet_release_selected.has(identifier)
		pick.toggled.connect(func(on):
			if on:pet_release_selected[identifier]=true
			else:pet_release_selected.erase(identifier)
			pet_release_confirm=false;rebuild());actions.add_child(pick)
		add_pet_favorite_button(actions,pet,"CompareFavorite_")
		var transfer:Button=world.button("存入仓库" if row.location=="pets" else "取出",func():
			var ok:bool=world.session.store_pet(int(row.index)) if row.location=="pets" else world.session.retrieve_pet_by_id(identifier)
			if ok:world.refresh_companion();world.checkpoint();feedback="已更新宠物位置。"
			else:feedback=world.session.last_error
			rebuild());transfer.name="CompareTransfer_"+identifier;transfer.disabled=(row.location=="pets" and int(row.index)==int(profile.get("ride_pet",-1))) or (row.location!="pets" and profile.pets.size()>=world.session.PET_CAPACITY);actions.add_child(transfer)
		if row.location=="pets":
			var deploy:Button=world.button("撤回" if int(row.index)==int(profile.active_pet) else "出战",func():
				if world.session.select_pet(-1 if int(row.index)==int(profile.active_pet) else int(row.index)):world.refresh_companion();world.checkpoint()
				rebuild());deploy.name="CompareDeploy_"+identifier;actions.add_child(deploy)
			if int(row.index)==int(profile.get("ride_pet",-1)):
				var dismount:Button=world.button("下骑",func():
					if world.session.mount_pet(-1):world.refresh_companion();world.checkpoint()
					rebuild());dismount.name="CompareDismount_"+identifier;actions.add_child(dismount)

	style_pet_modal(overlay)

func clear_release_selection()->void:
	pet_release_selected.clear();pet_release_confirm=false

func release_metric_value(pet:Dictionary,metric:String)->int:
	if metric=="stat_total":return int(pet.attack)+int(pet.defence)+int(pet.speed)
	return int(pet.get(metric,0))

func release_controls(overlay:Control,profile:Dictionary,rows:Array,top:float)->void:
	var bar:=HBoxContainer.new();bar.name="CompareReleaseBar";bar.position=Vector2(14,top);bar.add_theme_constant_override("separation",8);overlay.add_child(bar)
	var count:Label=world.text("已选 %d 只"%pet_release_selected.size(),14);count.name="CompareSelectedCount";bar.add_child(count)
	var page_all:Button=world.button("本页全选",func():
		for row in rows.slice(pet_compare_page*20,(pet_compare_page+1)*20):pet_release_selected[str(row.pet.get("pet_id",""))]=true
		pet_release_confirm=false;rebuild());page_all.name="CompareSelectPage";bar.add_child(page_all)
	var clear:Button=world.button("清除选择",func():clear_release_selection();rebuild());clear.name="CompareClearSelection";bar.add_child(clear)
	if pet_release_confirm:
		var confirm:Button=world.button("确认放生 %d 只"%pet_release_selected.size(),func():perform_release());confirm.name="CompareReleaseConfirm";confirm.add_theme_color_override("font_color",Color("ff8a7a"));bar.add_child(confirm)
		var cancel:Button=world.button("取消",func():pet_release_confirm=false;rebuild());cancel.name="CompareReleaseCancel";bar.add_child(cancel)
	else:
		var release:Button=world.button("放生所选 (%d)"%pet_release_selected.size(),func():
			if not pet_release_selected.is_empty():pet_release_confirm=true
			rebuild());release.name="CompareRelease";release.disabled=pet_release_selected.is_empty();release.tooltip_text="永久删除所选宠物；收藏、出战、骑乘的宠物会跳过。放生前自动备份存档。";bar.add_child(release)
	var picker:=HBoxContainer.new();picker.name="CompareThresholdBar";picker.position=Vector2(14,top+42);picker.add_theme_constant_override("separation",8);overlay.add_child(picker)
	picker.add_child(world.text("选择",14))
	var metric:=OptionButton.new();metric.name="CompareThresholdMetric";metric.focus_mode=Control.FOCUS_NONE
	for caption in ["三围合","攻击","防御","敏捷"]:metric.add_item(caption)
	metric.select(pet_release_metric);metric.item_selected.connect(func(i):pet_release_metric=i);picker.add_child(metric)
	picker.add_child(world.text("<",14))
	var below:=SpinBox.new();below.name="CompareThresholdValue";below.min_value=0;below.max_value=100000;below.step=1;below.value=pet_release_below;below.custom_minimum_size=Vector2(110,0)
	below.value_changed.connect(func(value):pet_release_below=int(value));picker.add_child(below)
	picker.add_child(world.text("的宠物（不含收藏／出战／骑乘）",14))
	var apply:Button=world.button("选择",func():
		if below.get_line_edit().has_focus():below.apply()
		pet_release_below=int(below.value)
		var added:=select_release_below(profile,rows,RELEASE_METRICS[pet_release_metric],pet_release_below)
		feedback="已按条件新增选择 %d 只。"%added;pet_release_confirm=false;rebuild());apply.name="CompareThresholdSelect";picker.add_child(apply)

func select_release_below(profile:Dictionary,rows:Array,metric:String,limit:int)->int:
	var added:=0
	for row in rows:
		var pet:Dictionary=row.pet;var identifier:=str(pet.get("pet_id",""))
		if identifier.is_empty() or pet.get("favorite",false) or pet_release_selected.has(identifier):continue
		if row.location=="pets" and (int(row.index)==int(profile.active_pet) or int(row.index)==int(profile.get("ride_pet",-1))):continue
		if release_metric_value(pet,metric)<limit:pet_release_selected[identifier]=true;added+=1
	return added

func perform_release()->void:
	var result:Dictionary=world.release_pets(pet_release_selected.keys())
	if not world.session.last_error.is_empty():feedback=world.session.last_error;pet_release_confirm=false;rebuild();return
	var skipped:Array=result.get("skipped",[])
	feedback="已放生 %d 只"%int(result.released)
	if not skipped.is_empty():feedback+="；跳过 %d 只（%s）"%[skipped.size(),"、".join(skipped.slice(0,4).map(func(item):return "%s %s"%[item.id,item.reason]))+("…" if skipped.size()>4 else "")]
	if not str(result.get("backup","")).is_empty():feedback+="；已备份存档 "+str(result.backup).get_file()
	clear_release_selection();rebuild()

func open_pet_comparison(pet_id:String)->bool:
	if world.battle_view.visible or world.area_transition_busy:return false
	var profile:Dictionary=world.session.snapshot()
	for location in ["pets","pet_storage"]:
		for pet in profile.get(location,[]):
			if str(pet.get("pet_id",""))==pet_id:
				pet_compare_subject=pet.duplicate(true);pet_compare_id=pet_id;pet_compare_open=true;world.clear_input();world.paused_input=true;world.classic_hud.map_panel.hide();open_menu("pets");return true
	return false

func pet_storage_panel(profile:Dictionary)->void:
	var overlay:=Panel.new();overlay.name="PetStoragePanel";overlay.position=Vector2.ZERO;overlay.z_index=10;overlay.mouse_filter=Control.MOUSE_FILTER_STOP;overlay.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"));overlay.size=Vector2(680,mini(600,160+maxi(1,mini(20,profile.get("pet_storage",[]).size()))*60));overlay.add_theme_stylebox_override("panel",world.box(Color("182324"),Color("b8a47c")));panel.add_child(overlay)
	var title:Label=world.text("宠物仓库 · %d只 · 携带%d/%d" % [profile.get("pet_storage",[]).size(),profile.pets.size(),world.session.PET_CAPACITY],18);title.position=Vector2(14,12);overlay.add_child(title)
	var close:Button=world.button("关闭",func():pet_storage_open=false;pet_view="list";rebuild());close.position=Vector2(575,8);overlay.add_child(close)
	var store_index:=-1
	for i in range(profile.pets.size()):
		if str(profile.pets[i].get("pet_id",""))==pet_storage_target_id:store_index=i
	var store:Button=world.button("存入 "+str(profile.pets[store_index].name) if store_index>=0 else "选中宠物已存入／未选择",func():
		if world.session.store_pet(store_index):world.refresh_companion();world.checkpoint();feedback="已存入仓库。"
		else:feedback=world.session.last_error
		rebuild());store.name="StoreSelectedPet";store.position=Vector2(14,50);store.disabled=store_index<0 or store_index==int(profile.get("ride_pet",-1));overlay.add_child(store)
	var note:Label=world.text("出战宠存入时自动撤回；骑乘宠须先下骑。存取保留属性；收藏优先。",13);note.position=Vector2(14,92);overlay.add_child(note)
	var scroll:=ScrollContainer.new();scroll.position=Vector2(14,125);scroll.size=Vector2(650,maxf(40,overlay.size.y-140));overlay.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var count:int=profile.get("pet_storage",[]).size();var pages:=maxi(1,ceili(count/20.0));pet_storage_page=clampi(pet_storage_page,0,pages-1)
	var previous:Button=world.button("◀",func():pet_storage_page=maxi(0,pet_storage_page-1);rebuild());previous.position=Vector2(310,50);overlay.add_child(previous)
	var next:Button=world.button("▶",func():pet_storage_page=mini(pages-1,pet_storage_page+1);rebuild());next.position=Vector2(500,50);overlay.add_child(next)
	var page:Label=world.text("%d/%d"%[pet_storage_page+1,pages],14);page.position=Vector2(405,56);overlay.add_child(page)
	var storage_rows:=PetComparison.storage_rows(profile)
	for entry in storage_rows.slice(pet_storage_page*20,(pet_storage_page+1)*20):
		var index:int=entry.index
		var pet:Dictionary=entry.pet
		var identifier:=str(pet.pet_id)
		var row:=HBoxContainer.new();row.name="StorageRow_"+identifier;list.add_child(row)
		var text:Label=world.text("%s Lv.%d · %s\n攻%d 防%d 敏%d · 三围合%d" % [pet.name,pet.level,pet.get("pet_id","?"),pet.attack,pet.defence,pet.speed,int(pet.attack)+int(pet.defence)+int(pet.speed)],14);text.name="StorageStats_"+identifier;text.custom_minimum_size=Vector2(270,56);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(text)
		add_pet_favorite_button(row,pet,"StorageFavorite_")
		var retrieve:Button=world.button("取出",func():
			if world.session.retrieve_pet_by_id(identifier):world.refresh_companion();world.checkpoint();feedback="已取出。"
			else:feedback=world.session.last_error
			rebuild());retrieve.name="RetrievePet_"+str(index);retrieve.disabled=profile.pets.size()>=world.session.PET_CAPACITY;row.add_child(retrieve)
		var compare:Button=world.button("同种比较",func():
			pet_compare_subject=pet.duplicate(true);pet_compare_open=true;rebuild());row.add_child(compare)

	style_pet_modal(overlay)

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
	var toggle:Button=world.button("★ 已收藏" if favorite else "☆ 收藏",func():
		if world.session.set_pet_favorite(identifier,not favorite):world.checkpoint();feedback="已取消收藏。" if favorite else "已收藏；仓库内优先显示。"
		else:feedback=world.session.last_error
		rebuild())
	toggle.name=prefix+identifier
	if favorite:toggle.modulate=Color("ffe680")
	parent.add_child(toggle)
