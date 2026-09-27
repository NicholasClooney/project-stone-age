extends Control
## Original resource frames with a narrow, functional single-player menu set.
var world: Node
var kind := "status"
var panel: Control
var feedback := ""
var selected_pet := 0
var pet_view := "list"
var pet_rename := false
var pet_category := "全部"
var pet_page := 0
var pet_growth_open := false
const PetGrowth = preload("res://scripts/pet_growth.gd")
var name_edit: LineEdit
var art: Dictionary = {}
var selected_item := "potion"
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
func rebuild() -> void:
	if world==null or not visible:return
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
			pet_panel(profile)
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
	view.texture = load("res://assets/legacy/mvp/images/%s.png" % item)
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
	return button

func portrait(sprite: int, point: Vector2, bounds: Vector2) -> void:
	var path := "res://assets/legacy/battle/manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var frames: Array = manifest.characters[str(sprite)]["3_0"].frames
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


func inventory_panel(profile: Dictionary) -> void:
	image(26060,Vector2.ZERO)
	image(26061,Vector2(0,159))
	label(str(profile.player.gold),Vector2(182,84),75,14)
	# Classic five-slot frame: InitItem menu.cpp8940-8973. Weapon is
	# CHAR_ARM=2 at(61,129), not the top-left accessory slot. The frame
	# already contains head/body/hand silhouettes; no invented mannequin.
	if profile.equipped:
		item_icon("club",Vector2(49,118)).name="EquippedClubIcon"
		var equipped_slot := choice("",Vector2(38,106),"",null)
		for connection in equipped_slot.pressed.get_connections():equipped_slot.pressed.disconnect(connection.callable)
		equipped_slot.name="EquippedClub"
		equipped_slot.size=Vector2(48,48)
		equipped_slot.tooltip_text="小棍棒 · 双击卸下"
		equipped_slot.pressed.connect(func(): selected_item="club";rebuild())
		equipped_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				world.perform_adventure_action("equip",false)
		)
	for i in range(2):
		var key := "potion" if i==0 else "club"
		# Authority inventory is total owned; equipment consumes one visible
		# bag copy without deleting ownership. Spare copies remain in the bag.
		var bag_count := maxi(0,int(profile.inventory[key])-(1 if key=="club" and profile.equipped else 0))
		if bag_count>0:
			var offset := Vector2(-11,-21) if key=="potion" else Vector2(-12,-11)
			item_icon(key,Vector2(32+i*51,200)+offset).name="BagIcon_"+key
			label(str(bag_count),Vector2(31+i*51,201),40,12).name="BagCount_"+key
		var slot := choice("",Vector2(11+i*51,175),"",null,bag_count>0)
		for connection in slot.pressed.get_connections():slot.pressed.disconnect(connection.callable)
		slot.name="ItemSlot_"+key
		slot.size=Vector2(48,48)
		slot.tooltip_text="耐久力回复药" if key=="potion" else "小棍棒 · 双击装备"
		slot.pressed.connect(func(): selected_item=key;rebuild())
		slot.gui_input.connect(func(event: InputEvent):
			if key=="club" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
				if not world.session.snapshot().equipped:world.perform_adventure_action("equip",true)
		)
	var potion := selected_item=="potion"
	label("耐久力回复药" if potion else "小棍棒",Vector2(15,328),240,15)
	label("恢复体力；战斗中也可使用。" if potion else "攻击 +4；装备后生效。",Vector2(15,354),239,14)
	choice("使用" if potion else ("卸下" if profile.equipped else "装备"),Vector2(14,404),"use_potion" if potion else "equip",null if potion else not profile.equipped,int(profile.inventory[selected_item])>0 and (not potion or int(profile.player.hp)<int(profile.player.max_hp)))

func pet_native_button(ident: int, center: Vector2, callback: Callable, title: String = "") -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = original(ident)
	button.position = center-button.texture_normal.get_size()/2
	button.tooltip_text = title
	button.pressed.connect(callback)
	panel.add_child(button)
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
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/battle/manifest.json"))
	var frame: Dictionary=manifest.characters[str(int(pet.sprite))]["3_0"].frames[0]
	var metadata: Dictionary=manifest.images[str(int(frame.image))]
	var portrait_view:=TextureRect.new()
	portrait_view.name="PetPortrait"
	portrait_view.texture=load("res://assets/legacy/battle/images/%d.png" % int(frame.image))
	portrait_view.position=Vector2(200+metadata.x+frame.x,144+metadata.y+frame.y)
	portrait_view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(portrait_view)
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

func pet_collection_tools(profile: Dictionary, filtered: Array) -> void:
	var origin:=Vector2(288,0)
	stone(Rect2(origin,Vector2(384,336) if pet_growth_open and not filtered.is_empty() else Vector2(256,336)))
	label("宠物收藏 · %d / %d" % [profile.pets.size(),world.session.PET_CAPACITY],origin+Vector2(16,14),235,16)
	var categories := ["全部","人龙","老虎","暴龙","乌力","其他"]
	var selector:=OptionButton.new()
	selector.name="PetCategory"
	selector.position=origin+Vector2(16,47)
	selector.size=Vector2(220,30)
	for category in categories:selector.add_item(category)
	selector.select(categories.find(pet_category))
	selector.item_selected.connect(func(index:int):pet_category=categories[index];pet_page=0;rebuild())
	panel.add_child(selector)
	var pages:=maxi(1,int(ceil(filtered.size()/5.0)))
	pet_page=clampi(pet_page,0,pages-1)
	label("第 %d / %d 页 · %d 只" % [pet_page+1,pages,filtered.size()],origin+Vector2(16,88),230,14)
	pet_native_button(26180,origin+Vector2(40,126),func(): change_pet_page(-1,filtered),"上一页")
	pet_native_button(26182,origin+Vector2(112,126),func(): change_pet_page(1,filtered),"下一页")
	label("黄色：出战　蓝色：[骑] 骑乘",origin+Vector2(16,154),230,12)
	if not filtered.is_empty():
		pet_tool_button("成长预估" if not pet_growth_open else "关闭成长预估",origin+Vector2(16,182),func(): pet_growth_open=not pet_growth_open;pet_view="detail";rebuild(),"PetGrowthToggle")
		var riding:=int(profile.get("ride_pet",-1))==selected_pet
		pet_tool_button("下骑" if riding else "骑乘选中伙伴",origin+Vector2(16,218),func():
			if world.session.mount_pet(-1 if riding else selected_pet):
				world.refresh_companion();world.checkpoint();feedback=""
			else:feedback=world.session.last_error
			rebuild(),"PetMount")
	pet_tool_button("DEV · 领取起始伙伴",origin+Vector2(16,254),func():
		if world.session.grant_starter_pets():
			world.refresh_companion();world.checkpoint();feedback="起始伙伴已加入（重复领取不增加）。"
		else:feedback="空间不足或当前不能领取。"
		rebuild(),"StarterPets")
	label(feedback,origin+Vector2(16,290),230,12)
	if pet_growth_open and not filtered.is_empty():pet_growth_panel(profile.pets[selected_pet],origin+Vector2(16,326))

func change_pet_page(delta:int,indices:Array)->void:
	var pages:=maxi(1,int(ceil(indices.size()/5.0)))
	pet_page=(pet_page+delta+pages)%pages
	if not indices.is_empty():selected_pet=int(indices[pet_page*5])
	pet_view="list"
	pet_growth_open=false
	rebuild()

func pet_growth_panel(pet: Dictionary, origin: Vector2) -> void:
	# Comparison level120 is a project choice, not the reference's level cap140.
	stone(Rect2(Vector2(288,336),Vector2(384,336)))
	var forecast:=PetGrowth.forecast(pet,120)
	if forecast.is_empty():
		label("缺少原始成长资料",origin,340,14)
		return
	label("%s · Lv.%d → %d 预估" % [pet.name,pet.level,forecast.target_level],origin+Vector2(0,20),350,15)
	var maxima:Dictionary=forecast.species_maximum
	for column in [["属性",0],["本宠预估",80],["同种上限",179],["差距",267]]:
		label(column[0],origin+Vector2(column[1],54),85,14)
	var keys: Array = ["max_hp","attack","defence","speed"]
	var names: Array = ["体力","攻击","防御","敏捷"]
	for i in range(4):
		var key:String=keys[i]
		var value:=int(forecast.expected[key])
		var upper:=int(maxima.get(key,0))
		var y:=86+i*25
		label(names[i],origin+Vector2(0,y),50,14)
		label(str(value),origin+Vector2(80,y),65,14)
		label(str(upper) if not maxima.is_empty() else "—",origin+Vector2(179,y),65,14)
		label(str(upper-value) if upper>=value else "超出%d" % (value-upper),origin+Vector2(267,y),85,14)
	var gains:Dictionary=forecast.base_increment
	label("每级基础成长：体 %.3f　腕 %.3f\n                         耐 %.3f　速 %.3f" % [gains.vitality,gains.strength,gains.toughness,gains.dexterity],origin+Vector2(0,196),350,13)
	var base:Dictionary=pet.base_stats
	label("当前基础：体 %.2f  腕 %.2f  耐 %.2f  速 %.2f" % [base.vitality/100.0,base.strength/100.0,base.toughness/100.0,base.dexterity/100.0],origin+Vector2(0,240),350,12)
	label("同种上限：从 Lv.1 培养、各项分别最优。\n每级共分配10点，四项上限不能同时达到。",origin+Vector2(0,268),350,12)
	var modified:bool=bool(pet.get("gm_modified",false)) or not pet.get("legacy_stat_offset",{}).is_empty()
	label("GM／旧存档修正可能超出原生成长上限。" if modified else "随机成长预估；不包含转生或 GM 加成。",origin+Vector2(0,310),350,11)

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
	for i in range(2):
		var key := "potion" if i==0 else "club"
		var caption := "耐久力回复药" if i==0 else "小棍棒"
		item_icon(key,Vector2(25,119+i*64))
		label(caption,Vector2(85,117+i*64),190,16)
		label("%d 石币    持有 %d" % [10 if i==0 else 30,profile.inventory[key]],Vector2(85,141+i*64),230,14)
		var row:=choice("",Vector2(18,111+i*64),"",null)
		for connection in row.pressed.get_connections():row.pressed.disconnect(connection.callable)
		row.size=Vector2(390,58)
		row.pressed.connect(func(): selected_item=key;rebuild())
	item_icon(selected_item,Vector2(43,319))
	label("耐久力回复药 · 恢复体力" if selected_item=="potion" else "小棍棒 · 攻击 +4",Vector2(111,310),300,15)
	label("售出 %d 石币" % (5 if selected_item=="potion" else 15),Vector2(111,338),200,14)
	art_button(26098,Vector2(231,382),"buy_"+selected_item,null,int(profile.player.gold)>=(10 if selected_item=="potion" else 30)).tooltip_text="购买一个"
	art_button(26097,Vector2(312,382),"sell_"+selected_item,null,int(profile.inventory[selected_item])>0 and (selected_item!="club" or not profile.equipped or int(profile.inventory.club)>1)).tooltip_text="卖出一个"
