extends PanelContainer
## Server-owned quest projection. Selection and navigation are purely local UI state.
const AutoPolicy=preload("res://scripts/quest_auto_policy.gd")
var world: Node
var body: VBoxContainer
var last_model := ""
var selected_id := -1
var selected_steps := {}
var detail_open := false
var narrow := false
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var list_position := 0
var detail_positions := {}
var viewport_size := Vector2.ZERO

func configure(owner: Node) -> void:
	world=owner
	name="QuestHelperMenu"
	z_index=60
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.97),Color("b29b65")))
	hide()
func open_menu() -> void:
	if world.battle_view.visible or world.dialogue.visible:return
	world.quest_helper_travel.cancel()
	rebuild()
	show()
	world.clear_input()
	world.paused_input=true
func close_menu() -> void:
	remember_scroll()
	world.quest_helper_travel.cancel()
	hide()
	world.paused_input=world.battle_view.visible or world.automation_minimized()
	world.clear_input()
func relayout() -> void:
	var available:Vector2=world.get_viewport_rect().size
	custom_minimum_size=Vector2.ZERO
	size=Vector2(minf(1100,available.x-16),maxf(180,available.y-32))
	position=(available-size)/2
func model() -> Dictionary:
	return world.state.derived.get("quest_helper",{})
func refresh_key() -> String:
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	return JSON.stringify([model(),auto.get("running",false),auto.get("quest_id",-1),world.quest_helper_travel.active])
func _process(_delta: float) -> void:
	if not visible:return
	if refresh_key()!=last_model or viewport_size!=world.get_viewport_rect().size:rebuild()
	var status=find_child("QuestAutoMessage",true,false)
	if status is Label:status.text=str(world.state.derived.get("quest_auto",{}).get("message",""))
func remember_scroll() -> void:
	if is_instance_valid(list_scroll) and list_scroll.is_visible_in_tree():list_position=list_scroll.scroll_vertical
	if is_instance_valid(detail_scroll) and detail_scroll.is_visible_in_tree():detail_positions[selected_id]=detail_scroll.scroll_vertical
func select_quest(id:int) -> void:
	remember_scroll()
	selected_id=id
	detail_open=true
	rebuild(false)
func back_to_list() -> void:
	remember_scroll()
	detail_open=false
	rebuild(false)
func label(parent:Node,value:String,font_size:int=14) -> Label:
	var result:Label=world.text(value,font_size)
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result
func button(parent:Node,value:String,action:Callable,id:String="") -> Button:
	var result:Button=world.button(value,action)
	if not id.is_empty():result.name=id
	result.custom_minimum_size.y=44
	result.add_theme_font_size_override("font_size",16)
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result
func scroll(parent:Node,id:String) -> ScrollContainer:
	var result:=ScrollContainer.new()
	result.name=id
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.size_flags_vertical=Control.SIZE_EXPAND_FILL
	result.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(result)
	return result
func column(parent:Node) -> VBoxContainer:
	var result:=VBoxContainer.new()
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("separation",8)
	parent.add_child(result)
	return result
func group_for(quest:Dictionary) -> String:
	if str(quest.status)=="进行中":return "当前任务"
	if str(quest.status)=="已完成":return "已完成"
	if str(quest.get("blocked_reason","" )).is_empty():
		for step in quest.get("steps",[]):
			if step.get("current",false) and step.get("actionable",false) and str(step.get("source",{}).get("type",""))=="REQUEST":return "可接任务"
	return "未开始"
func quest_row(parent:Node,quest:Dictionary) -> void:
	var row:=button(parent,str(quest.title)+" · "+str(quest.status),func():select_quest(int(quest.id)),"QuestHelper_%s"%quest.id)
	row.alignment=HORIZONTAL_ALIGNMENT_LEFT
	row.toggle_mode=true
	row.button_pressed=int(quest.id)==selected_id
	row.tooltip_text=str(quest.get("blocked_reason",""))
func rebuild(save_scroll:bool=true) -> void:
	if save_scroll:remember_scroll()
	viewport_size=world.get_viewport_rect().size
	narrow=viewport_size.x<720
	last_model=refresh_key()
	for child in get_children():remove_child(child);child.queue_free()
	list_scroll=null;detail_scroll=null
	body=column(self)
	var header:=HBoxContainer.new();body.add_child(header)
	label(header,"任务助手",20)
	var close:=button(header,"关闭 · Esc",close_menu,"QuestHelperClose")
	close.size_flags_horizontal=Control.SIZE_SHRINK_END
	close.custom_minimum_size.x=110
	close.autowrap_mode=TextServer.AUTOWRAP_OFF
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.get("running",false) or world.quest_helper_travel.active:
		button(body,"停止自动任务 / 导航",func():world.quest_helper_travel.cancel();rebuild(),"QuestAutoStop")
		label(body,str(auto.get("message","")),12).name="QuestAutoMessage"
	var panes:=HBoxContainer.new();panes.size_flags_vertical=Control.SIZE_EXPAND_FILL;panes.add_theme_constant_override("separation",20);body.add_child(panes)
	var quests:Array=model().get("quests",[])
	var selected:Dictionary={}
	for quest in quests:
		if int(quest.id)==selected_id:selected=quest
	if selected.is_empty() and not quests.is_empty():
		selected=quests[0]
		for quest in quests:
			if group_for(quest)=="当前任务":selected=quest;break
		selected_id=int(selected.id)
	var listing:=column(panes)
	listing.size_flags_vertical=Control.SIZE_EXPAND_FILL
	listing.visible=not narrow or not detail_open
	if not narrow:listing.custom_minimum_size.x=280;listing.size_flags_stretch_ratio=0.85
	label(listing,"当前任务",16)
	var current:=scroll(listing,"QuestCurrentScroll")
	current.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	var current_list:=column(current)
	var current_count:=0
	for quest in quests:
		if group_for(quest)=="当前任务":quest_row(current_list,quest);current_count+=1
	if current_count==0:label(current_list,"暂无进行中的任务",12)
	current.custom_minimum_size.y=minf(144, maxf(28,current_count*52))
	list_scroll=scroll(listing,"QuestListScroll")
	var rows:=column(list_scroll)
	for group in ["可接任务","未开始","已完成"]:
		var entries:Array=quests.filter(func(q):return group_for(q)==group)
		if entries.is_empty():continue
		label(rows,"%s · %d"%[group,entries.size()],14)
		for quest in entries:quest_row(rows,quest)
	list_scroll.set_deferred("scroll_vertical",list_position)
	var details:=column(panes)
	details.size_flags_vertical=Control.SIZE_EXPAND_FILL
	details.size_flags_stretch_ratio=1.7
	details.visible=not narrow or detail_open
	if narrow:button(details,"‹ 返回任务列表",back_to_list,"QuestHelperBack")
	detail_scroll=scroll(details,"QuestDetailScroll")
	var content:=column(detail_scroll)
	if selected.is_empty():label(content,"暂无任务")
	else:build_detail(content,selected)
	detail_scroll.set_deferred("scroll_vertical",int(detail_positions.get(selected_id,0)))
	relayout()
func build_detail(content:VBoxContainer,quest:Dictionary) -> void:
	label(content,str(quest.title),20)
	label(content,str(quest.status)+(" · 可重做" if quest.get("can_restart",false) else ""),12)
	if not str(quest.get("blocked_reason","")).is_empty():label(content,str(quest.blocked_reason),13)
	if AutoPolicy.supports(int(quest.id),int(quest.event)) and not world.state.derived.get("quest_auto",{}).get("running",false):
		var action:=button(content,"自动重做" if quest.get("can_restart",false) else "自动执行",func():world.quest_helper_travel.start_auto(int(quest.id));rebuild(),"QuestAutoStart_%s"%quest.id)
		action.disabled=(str(quest.status)=="已完成" and not quest.get("can_restart",false)) or not str(quest.get("blocked_reason","")).is_empty()
		label(content,"自动执行会确认原交易；停止、关闭或 Esc 可中止。",12)
	var steps:Array=quest.get("steps",[])
	var chosen:Dictionary={}
	for step in steps:
		if str(step.id)==str(selected_steps.get(int(quest.id),"")):chosen=step
	if chosen.is_empty():
		for step in steps:
			if step.get("current",false):chosen=step;break
	if chosen.is_empty() and not steps.is_empty():chosen=steps[0]
	if not chosen.is_empty():
		label(content,"当前步骤" if chosen.get("current",false) else "所选步骤",14)
		label(content,str(chosen.label),15)
		if int(chosen.get("map_id",-1))>=0 and chosen.get("cell",[]).size()==2:
			var actions:=HBoxContainer.new();content.add_child(actions)
			for mode in ["near","arrival"]:
				var target:Dictionary=chosen.duplicate(true);target.quest_id=int(quest.id)
				var visit:=button(actions,"瞬移" if mode=="near" else "到地图走过去",func():
					remember_scroll();hide();world.paused_input=false;world.quest_helper_travel.visit(target,mode),("QuestVisit_%s_%s_%s"%[quest.id,chosen.id,mode]).validate_node_name())
				visit.set_meta("quest_step",target);visit.set_meta("visit_mode",mode)
	label(content,"任务步骤 · 点击选择地点",14)
	for index in range(steps.size()):
		var step:Dictionary=steps[index]
		var row:=button(content,("▶ " if step.get("current",false) else ("✓ " if step.get("done",false) else "%d. "%[index+1]))+str(step.label),func():
			selected_steps[int(quest.id)]=str(step.id);detail_positions[selected_id]=0;rebuild(false),"QuestStep_%s_%s"%[quest.id,str(step.id).validate_node_name()])
		row.alignment=HORIZONTAL_ALIGNMENT_LEFT
		row.toggle_mode=true;row.button_pressed=str(step.id)==str(chosen.get("id",""))
	if not str(quest.get("completion_detail","")).is_empty():label(content,str(quest.completion_detail),12)
