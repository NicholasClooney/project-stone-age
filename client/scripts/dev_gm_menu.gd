extends Control
## Explicit developer tools: no original-game UI claim and no mutation on open.
var world: Node
var panel: Panel
var actor_picker: OptionButton
var level_input: SpinBox
var point_input: SpinBox
var stat_inputs: Dictionary={}
var feedback: Label
var summary: Label
var mutation_buttons: Array[Button]=[]
var clear_selected_button: Button
var clear_all_button: Button
var escape_button: Button
var previous_pause := false
func configure(owner: Node)->void:world=owner
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=200
	panel=Panel.new()
	panel.position=Vector2(160,100)
	panel.size=Vector2(960,565)
	panel.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")))
	add_child(panel)
	_label("DEV / GM · 当前存档调试",Vector2(24,18),22)
	_label("操作会保存，并标记 GM 修改。基础值单位：1.00 = 100 原始固定点。",Vector2(24,52),15)
	actor_picker=OptionButton.new()
	actor_picker.position=Vector2(24,92)
	actor_picker.size=Vector2(380,32)
	actor_picker.item_selected.connect(func(_index:int):_refresh_actor())
	panel.add_child(actor_picker)
	level_input=_number(Vector2(24,145),1,120,1,120)
	_action("升至等级",Vector2(175,145),func():_apply(world.session.gm_raise_level(_actor(),level_input.value)))
	_label("保留成长种子；相同等级不会重复成长。只升不降。",Vector2(335,154),14)
	var row:=0
	for key in ["vitality","strength","toughness","dexterity"]:
		var title: String={"vitality":"体力 V","strength":"腕力 S","toughness":"耐力 T","dexterity":"速度 D"}[key]
		_label(title,Vector2(24,204+row*47),16)
		var input:=_number(Vector2(130,195+row*47),-10000,10000,0.01,0)
		stat_inputs[key]=input
		_action("设置基础值",Vector2(280,195+row*47),func():_apply(world.session.gm_set_base_stat(_actor(),key,input.value,false)))
		_action("增加基础值",Vector2(450,195+row*47),func():_apply(world.session.gm_set_base_stat(_actor(),key,input.value,true)))
		row+=1
	point_input=_number(Vector2(24,393),1,100000,1,3)
	_action("赠送角色分配点",Vector2(175,393),func():_apply(world.session.gm_grant_points(point_input.value)))
	_action("恢复所选体力",Vector2(405,393),func():_apply(world.session.gm_heal(_actor())))
	_action("恢复全队体力",Vector2(620,393),func():_apply(world.session.gm_heal(-2)))
	escape_button=world.button("立即脱战 · 无奖励",_escape)
	escape_button.position=Vector2(24,440)
	panel.add_child(escape_button)
	clear_selected_button=_action("清除所选 GM 标记",Vector2(300,440),func():_apply(world.session.gm_clear_modified(_actor()),true))
	clear_all_button=_action("清除全队 GM 标记",Vector2(580,440),func():_apply(world.session.gm_clear_modified(-2),true))
	for button in [clear_selected_button,clear_all_button]:
		button.tooltip_text="仅清除标记，不恢复数值；清除后不代表自然培养。全队指主角和全部真实宠物。"
	var close: Button=world.button("关闭 · Esc",close_menu)
	close.position=Vector2(770,490)
	panel.add_child(close)
	summary=_label("",Vector2(620,198),15)
	summary.size=Vector2(305,180)
	feedback=_label("",Vector2(24,495),14)
	feedback.size=Vector2(725,54)
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hide()
func _label(value:String,position:Vector2,font_size:int)->Label:
	var label:Label=world.text(value,font_size)
	label.position=position
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label
func _number(position:Vector2,minimum:float,maximum:float,step:float,value:float)->SpinBox:
	var field:=SpinBox.new()
	field.position=position
	field.size=Vector2(132,34)
	field.min_value=minimum
	field.max_value=maximum
	field.step=step
	field.value=value
	panel.add_child(field)
	return field
func _action(title:String,position:Vector2,callback:Callable)->Button:
	var button:Button=world.button(title,callback)
	button.position=position
	panel.add_child(button)
	mutation_buttons.append(button)
	return button
func _actor()->int:return actor_picker.get_selected_id()
func open_menu()->void:
	if world.paused_input and not world.battle_view.visible:return
	previous_pause=world.paused_input
	world.clear_input()
	world.paused_input=true
	actor_picker.clear()
	actor_picker.add_item("角色",0)
	actor_picker.set_item_id(0,-1)
	var profile:Dictionary=world.session.snapshot()
	for i in range(profile.pets.size()):actor_picker.add_item("%s · Lv.%d" % [profile.pets[i].name,profile.pets[i].level],i)
	feedback.text="战斗中能力修改已锁定；可立即脱战。" if world.battle_view.visible else "选择对象后操作；打开面板不会改变存档。"
	_refresh_actor()
	move_to_front()
	show()
func close_menu()->void:
	hide()
	world.paused_input=previous_pause
	world.clear_input()
func _refresh_actor()->void:
	var profile:Dictionary=world.session.snapshot()
	var actor:Dictionary=profile.player if _actor()==-1 else profile.pets[_actor()]
	for stat in stat_inputs:stat_inputs[stat].value=float(actor.base_stats.get(stat,0))/100.0
	level_input.value=120
	summary.text="Lv.%d%s\n体力 %d / %d\n攻击 %d　防御 %d\n速度 %d\n角色可分配点 %d" % [actor.level," · GM已修改" if actor.get("gm_modified",false) else "",actor.hp,actor.max_hp,actor.attack,actor.defence,actor.speed,profile.player.stat_points]
	for button in mutation_buttons:button.disabled=world.battle_view.visible or not world.session._pending.is_empty()
	escape_button.disabled=not world.battle_view.visible or not world.battle_session.snapshot().get("active",false)
func _apply(success:bool,cleared:bool=false)->void:
	feedback.text=world.session.last_error if not success else ""
	if success:
		var saved: bool=world.checkpoint()
		feedback.text=("标记已清除并保存；数值未恢复，不代表自然培养。" if cleared else "已修改并保存 · GM 标记已保留。") if saved else "已修改，但保存失败；请检查存储空间。"
		world.refresh_companion()
		_refresh_actor()
func _escape()->void:
	if not world.battle_view.visible or not world.battle_session.snapshot().get("active",false):return
	close_menu()
	world.battle_view.pending_action="escape"
	world.battle_action("developer_escape")
