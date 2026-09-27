extends Control
## Original resource frames with a narrow, functional single-player menu set.
var world: Node
var kind := "status"
var panel: Control
var feedback := ""
var selected_pet := 0
var name_edit: LineEdit
var art: Dictionary = {}
var selected_item := "potion"
func configure(owner: Node) -> void:
	world = owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(layout_panel)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hide()
func _has_point(point: Vector2) -> bool:
	# Leave the original bottom menu reachable while blocking world/dev clicks.
	return point.y < size.y-40

func open_menu(next_kind: String) -> void:
	kind = next_kind
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
	item.position = point
	item.size.x = width
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_color_override("font_color",Color.WHITE)
	item.add_theme_color_override("font_shadow_color",Color.BLACK)
	item.add_theme_constant_override("shadow_offset_x",1)
	item.add_theme_constant_override("shadow_offset_y",1)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var dimensions := {"status":Vector2(272,360),"inventory":Vector2(272,440),"pets":Vector2(552,380),"shop":Vector2(432,468)}
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
			choice("保存旅程",Vector2(420,90),"save",null,world.profile_persistence)
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

func item_icon(item: String, point: Vector2) -> void:
	var view := TextureRect.new()
	view.texture = load("res://assets/legacy/mvp/images/%s.png" % item)
	view.position = point
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(view)

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
	image(26073,Vector2.ZERO)
	label("旅行者",Vector2(22,43),140,14)
	portrait(100000,Vector2(177,84),Vector2(64,68))
	var values := [str(p.level),str(p.xp),str(int(p.level)*30-int(p.xp)),"%d / %d" % [p.hp,p.max_hp],"—",str(int(p.attack)+(4 if profile.equipped else 0)),str(p.defence),str(p.get("speed",10)),"—"]
	for i in range(values.size()):label(values[i],Vector2(87,70+i*21),83,13)
	var base_positions := [Vector2(80,289),Vector2(200,289),Vector2(80,311),Vector2(200,311)]
	var base_keys := ["vitality","strength","toughness","dexterity"]
	for i in range(base_keys.size()):label(str(p.allocated_stats[base_keys[i]]),base_positions[i],28,13)
	label("石币 %d   剩余点数 %d" % [p.gold,p.get("stat_points",0)],Vector2(18,331),248,13)
	var stats := ["vitality","strength","toughness","dexterity"]
	var rows := [Vector2(109,289),Vector2(229,289),Vector2(109,311),Vector2(229,311)]
	var hints := ["体力：最大体力 +4","腕力：攻击 +1","耐力：防御 +1","速度：敏捷 +1"]
	for i in range(stats.size()):
		var plus := art_button(26076,rows[i],"allocate_stat",stats[i],int(p.get("stat_points",0))>0)
		plus.texture_pressed = original(26077)
		plus.tooltip_text = hints[i] + "（消耗 1 点）"
		plus.name = "Allocate_"+stats[i]


func inventory_panel(profile: Dictionary) -> void:
	image(26060,Vector2.ZERO)
	image(26061,Vector2(0,159))
	label(str(profile.player.gold),Vector2(182,84),75,14)
	if profile.equipped:item_icon("club",Vector2(15,46))
	for i in range(2):
		var key := "potion" if i==0 else "club"
		if int(profile.inventory[key])>0:
			item_icon(key,Vector2(18+i*51,171))
			label(str(profile.inventory[key]),Vector2(31+i*51,201),40,12)
		var slot := choice("",Vector2(11+i*51,164),"",null,int(profile.inventory[key])>0)
		for connection in slot.pressed.get_connections():slot.pressed.disconnect(connection.callable)
		slot.size=Vector2(48,48)
		slot.tooltip_text="耐久力回复药" if key=="potion" else "小棍棒"
		slot.pressed.connect(func(): selected_item=key;rebuild())
	var potion := selected_item=="potion"
	label("耐久力回复药" if potion else "小棍棒",Vector2(15,328),240,15)
	label("恢复体力；战斗中也可使用。" if potion else "攻击 +4；装备后生效。",Vector2(15,354),239,14)
	choice("使用" if potion else ("卸下" if profile.equipped else "装备"),Vector2(14,404),"use_potion" if potion else "equip",null if potion else not profile.equipped,int(profile.inventory[selected_item])>0 and (not potion or int(profile.player.hp)<int(profile.player.max_hp)))

func pet_panel(profile: Dictionary) -> void:
	image(26044,Vector2.ZERO)
	var pets: Array = profile.pets
	if pets.is_empty():
		stone(Rect2(280,0,256,240))
		label("还没有宠物。\n在村外削弱野生宠物后，\n使用战斗菜单的捕捉。",Vector2(298,34),218,15)
		return
	image(26045,Vector2(280,0))
	selected_pet=clampi(selected_pet,0,pets.size()-1)
	for i in range(pets.size()):
		var pet: Dictionary=pets[i]
		var y := 30+i*52
		portrait(int(pet.sprite),Vector2(15,y),Vector2(58,48))
		label(("★ " if int(profile.active_pet)==i else "")+str(pet.name),Vector2(77,y+1),180,13)
		label(str(pet.level),Vector2(108,y+26),35,13)
		label(str(pet.hp),Vector2(181,y+26),40,13)
		label(str(pet.max_hp),Vector2(230,y+26),40,13)
		var row:=choice("",Vector2(10,y),"pet_preview",i)
		row.size=Vector2(250,50)
		row.name="PetRow%d" % i
	var pet: Dictionary=pets[selected_pet]
	label(pet.name,Vector2(297,45),225,15)
	portrait(int(pet.sprite),Vector2(455,57),Vector2(64,74))
	var values := [str(pet.level),str(pet.xp),str(int(pet.level)*30-int(pet.xp)),"%d / %d" % [pet.hp,pet.max_hp],str(pet.attack),str(pet.defence),str(pet.speed),"—"]
	for i in range(values.size()):label(values[i],Vector2(366,85+i*22),90,13)
	label("强力攻击已学会" if pet.skill_unlocked else "Lv 2 学会强力攻击",Vector2(295,277),240,14)
	name_edit=LineEdit.new()
	name_edit.text=pet.name
	name_edit.max_length=16
	name_edit.position=Vector2(9,285)
	name_edit.size=Vector2(175,28)
	name_edit.add_theme_font_size_override("font_size",14)
	name_edit.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	panel.add_child(name_edit)
	art_button(26058,Vector2(183,289),"rename_pet",selected_pet).tooltip_text="更改名字"
	art_button(26054,Vector2(291,308),"select_pet",selected_pet).tooltip_text="设为出战与跟随宠物"

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
