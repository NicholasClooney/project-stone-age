extends Control
## Classic guide context plus verified destinations from the local source revision.
const DATA = preload("res://scripts/leveling_routes.gd")
var world: Node
var level: SpinBox
var choices: ItemList
var details: Label
var classic: Label
var spots: Array=[]
var ranked: Array=[]
var visit_button: Button
func configure(owner: Node) -> void:world=owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;z_index=500
	var panel:=Panel.new();panel.position=Vector2(80,125);panel.size=Vector2(1120,610)
	panel.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(panel)
	add_label(panel,"刷怪传送 · Lv.1–120 练级路线",Vector2(24,18),23)
	add_label(panel,"按怪物等级推荐当前可用区域；不是实测经验/分钟最优。镜像队可尝试更高级的敌人。",Vector2(24,62),16)
	add_label(panel,"目标等级",Vector2(24,116),17)
	level=SpinBox.new();level.position=Vector2(140,105);level.size=Vector2(150,38);level.min_value=1;level.max_value=120;panel.add_child(level)
	level.value_changed.connect(func(_value):refresh())
	var current: Button=world.button("使用我的等级",func():level.value=world.session.snapshot().player.level);current.position=Vector2(325,105);panel.add_child(current)
	classic=add_label(panel,"",Vector2(24,160),16);classic.size=Vector2(1070,88);classic.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	choices=ItemList.new();choices.position=Vector2(24,265);choices.size=Vector2(1070,175);choices.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"));choices.add_theme_font_size_override("font_size",16)
	choices.item_selected.connect(show_choice);choices.item_activated.connect(func(index):visit(index));panel.add_child(choices)
	details=add_label(panel,"",Vector2(24,455),16);details.size=Vector2(1070,80);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	visit_button=world.button("传送到选中刷怪点",func():
		var selected: PackedInt32Array=choices.get_selected_items()
		if not selected.is_empty():visit(selected[0]))
	visit_button.position=Vector2(24,555);panel.add_child(visit_button)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(930,555);panel.add_child(close)
	if FileAccess.file_exists("res://data/training-spots.json"):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://data/training-spots.json"))
		if parsed is Dictionary:spots=parsed.get("spots",[])
	hide()
func add_label(parent: Control,text: String,point: Vector2,font_size: int) -> Label:
	var label: Label=world.text(text,font_size);label.position=point;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(label);return label
func open_menu() -> void:
	if world.paused_input or world.moving or world.area_transition_busy:return
	world.clear_input();world.paused_input=true
	if is_instance_valid(world.travel_router):world.travel_router.cancel("打开练级路线。")
	get_parent().move_child(self,get_parent().get_child_count()-1)
	level.value=clampi(int(world.session.snapshot().player.level),1,120);refresh();show()
func close_menu() -> void:
	hide();world.paused_input=false;world.clear_input()
func refresh() -> void:
	if not is_instance_valid(choices):return
	classic.text=DATA.classic_guide(int(level.value))+"\n经典攻略与当前原表版本有差异；任务、水雷和缺动画的敌群不加入下方可用推荐。"
	ranked=DATA.recommend(spots,int(level.value),world.session.clone_squad_enabled)
	choices.clear()
	for spot in ranked:
		choices.add_item("%s%s · 怪物 Lv.%d–%d · (%d, %d)"%["推荐：" if choices.item_count==0 else "备选：",spot.name,spot.level_min,spot.level_max,spot.cell[0],spot.cell[1]])
	visit_button.disabled=ranked.is_empty()
	if not ranked.is_empty():choices.select(0);show_choice(0)
	else:details.text="当前没有验证通过的练级区。请先导入原版地图、怪物动画并生成练级地点数据。"
func show_choice(index: int) -> void:
	var spot: Dictionary=ranked[index]
	details.text="常见敌人：%s。\n传送后可开启「自动练级」。这里只提供场景和普通遇敌；DEV 直达不代表任务或门禁已恢复。"%"、".join(spot.monsters)
func visit(index: int) -> bool:
	if index<0 or index>=ranked.size() or world.area_transition_busy or world.battle_session.snapshot().active:return false
	var spot: Dictionary=ranked[index]
	var point:=Vector2i(spot.cell[0],spot.cell[1])
	var area: Dictionary=world.encounter_catalog.area_at(int(spot.map_id),point)
	if area.is_empty() or int(area.id)!=int(spot.area_id):details.text="原表已改变，请重新生成练级地点。";return false
	var checked: Vector2i=world.travel_landing.safe_destination(int(spot.map_id),point)
	if checked!=point:details.text="该落点已不可用，请选择其他练级区。";return false
	close_menu()
	return world.load_area_id(int(spot.map_id),point)
