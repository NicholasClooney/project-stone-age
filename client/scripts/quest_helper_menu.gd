extends PanelContainer
## Server-owned quest projection. Selection and navigation are purely local UI state.
const AutoSettings=preload("res://scripts/quest_auto_settings.gd")
const AutoPolicy=preload("res://scripts/quest_auto_policy.gd")
var settings_open:=false
var settings_pending:=false
var settings_feedback:=""
var settings_panel:Control
var world: Node
var body: VBoxContainer
var header: HBoxContainer
var settings_button: Button
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
	world.quest_helper_travel.cancel_navigation()
	rebuild()
	show()
	move_to_front()
	world.clear_input()
	world.paused_input=true
func close_menu() -> void:
	remember_scroll()
	world.quest_helper_travel.cancel_navigation()
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
	var loot:Dictionary=world.quest_helper_travel.public_loot_ui_state()
	return JSON.stringify([model(),auto.get("running",false),auto.get("quest_id",-1),str(auto.get("phase","")),auto.get("can_continue",false),auto.get("revision",-1),auto.get("effective_mode",""),auto.get("strict_walk",false),world.quest_helper_travel.active,auto.get("source_entry",{}),loot.visible,loot.can_start,loot.reason,loot.link_ready,loot.pending,loot.waiting_snapshot,loot.feedback])
func _process(_delta: float) -> void:
	if not visible:return
	if settings_open:
		if is_instance_valid(settings_panel):
			var online:bool=world.link.is_local() or world.link.online
			settings_panel.apply_button.disabled=settings_pending or not online or not world.state.derived.get("quest_auto",{}).has("settings")
		relayout()
		return
	if refresh_key()!=last_model or viewport_size!=world.get_viewport_rect().size:rebuild()
	var status=find_child("QuestAutoMessage",true,false)
	if status is Label:status.text=world.quest_helper_travel.auto_status()
	# Container minimum sizes settle after rebuilding; keep window chrome on screen.
	relayout()
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
	# Window actions outlive projection refreshes: replacing them between mouse
	# hover/press/release loses the user's click while background state updates.
	if not is_instance_valid(body):
		body=column(self)
		header=HBoxContainer.new();body.add_child(header)
		label(header,"任务助手",20)
		var minimize:=button(header,"最小化",close_menu,"QuestHelperMinimize")
		minimize.size_flags_horizontal=Control.SIZE_SHRINK_END
		minimize.autowrap_mode=TextServer.AUTOWRAP_OFF
		var close:=button(header,"关闭 · Esc",close_menu,"QuestHelperClose")
		close.size_flags_horizontal=Control.SIZE_SHRINK_END
		close.custom_minimum_size.x=110
		close.autowrap_mode=TextServer.AUTOWRAP_OFF
		settings_button=button(body,"自动任务设置",func():settings_open=true;settings_feedback="";rebuild(),"QuestAutoSettingsOpen")
	for child in body.get_children():
		if child==header or child==settings_button:continue
		body.remove_child(child)
		child.queue_free()
	list_scroll=null;detail_scroll=null;settings_panel=null
	settings_button.visible=not settings_open
	if settings_open:
		var settings_scroll:=scroll(body,"QuestAutoSettingsScroll")
		settings_panel=AutoSettings.new()
		settings_scroll.add_child(settings_panel)
		settings_panel.apply_requested.connect(save_auto_settings)
		settings_panel.back_requested.connect(func():settings_open=false;rebuild())
		present_auto_settings()
		relayout()
		return
	append_public_loot_start(body)
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.get("running",false) or world.quest_helper_travel.active:
		button(body,"停止自动任务 / 导航",func():world.quest_helper_travel.cancel();rebuild(),"QuestAutoStop")
		label(body,world.quest_helper_travel.auto_heading(),12)
		if str(auto.get("phase","")) in ["waiting_boss","waiting_reward"]:
			label(body,world.quest_helper_travel.auto_mode(),12)
		if str(auto.get("phase",""))=="waiting_boss":
			var resume:=button(body,"胜利后继续任务",func():world.quest_helper_travel.continue_auto(auto.duplicate(true)),"QuestAutoContinue")
			resume.disabled=not auto.get("can_continue",false) or not (world.link.is_local() or world.link.online)
		if str(auto.get("phase",""))=="waiting_reward":
			var reward:=button(body,"选择任务奖励",func():
				close_menu();world.quest_helper_travel.open_auto_reward(),"QuestAutoReward")
			reward.disabled=auto.get("waiting",{}).get("dialogue",{}).is_empty() or not (world.link.is_local() or world.link.online)
			label(body,"请选择原任务奖励；成功选择并保存后自动继续。取消或失败不会继续。",12)
		label(body,world.quest_helper_travel.auto_status(),12).name="QuestAutoMessage"
	elif str(auto.get("phase",""))=="manual":
		label(body,"已停止 · 待手动处理；处理后请再次点击自动推进。",12)
		label(body,world.quest_helper_travel.auto_status(),12).name="QuestAutoMessage"
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

func append_public_loot_start(parent:Node)->void:
	var state:Dictionary=world.quest_helper_travel.public_loot_ui_state()
	if not state.visible:return
	label(parent,"低血量时自动停下，交给玩家手动接管。",12).name="QuestLootSafetyNotice"
	var action:=button(parent,"开始限时刷物",func():world.quest_helper_travel.start_public_loot(),"QuestLootStart")
	action.disabled=not state.can_start or state.pending or state.waiting_snapshot or not state.link_ready
	if state.pending:
		label(parent,str(state.feedback),12).name="QuestLootStartFeedback"
	elif state.waiting_snapshot:
		label(parent,str(state.feedback),12).name="QuestLootStartFeedback"
	elif not state.can_start:
		var reason:String=str(state.reason)
		if reason.is_empty():reason="服务端当前未提供开始资格。"
		label(parent,reason,12).name="QuestLootStartReason"
	elif not state.link_ready:
		label(parent,"服务连接尚未就绪。",12).name="QuestLootStartReason"
	if not state.feedback.is_empty() and not state.pending and not state.waiting_snapshot:
		label(parent,str(state.feedback),12).name="QuestLootStartFeedback"

func build_detail(content:VBoxContainer,quest:Dictionary) -> void:
	var source_job:bool=int(quest.id)==2
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	var source_entry:Dictionary=auto.get("source_entry",{})
	label(content,str(quest.title),20)
	label(content,str(quest.status)+(" · 可重做" if quest.get("can_restart",false) else ""),12)
	if source_job:
		var reason:String=str(source_entry.get("reason","当前服务尚未提供原道场自动入口。"))
		if not reason.is_empty():label(content,reason,13).name="QuestAutoSourceReason"
	elif not str(quest.get("blocked_reason","")).is_empty():label(content,str(quest.blocked_reason),13)
	if AutoPolicy.supports(int(quest.id),int(quest.event)) and not world.state.derived.get("quest_auto",{}).get("running",false):
		var strict:bool=source_job or int(quest.id) in [12,13,24,25,5,9]
		var action:=button(content,("自动推进" if strict else ("自动重做" if quest.get("can_restart",false) else "自动执行")),func():world.quest_helper_travel.start_auto(int(quest.id));rebuild(),"QuestAutoStart_%s"%quest.id)
		if source_job:
			action.disabled=int(source_entry.get("job_id",-1))!=2 or not source_entry.get("enabled",false) or not source_entry.get("can_start",false) or not (world.link.is_local() or world.link.online)
		else:action.disabled=(str(quest.status)=="已完成" and not quest.get("can_restart",false)) or not str(quest.get("blocked_reason","")).is_empty()
		if not source_job:
			label(content,("仅推进当前所选任务，不会自动接续尚未开放的任务链。普通随机战成功后继续；Boss 由玩家手动战斗，胜利后按继续；奖励等待玩家选择，成功保存后继续当前任务。最终转生确认和交宠仍由玩家操作。" if world.state.derived.get("quest_auto",{}).has("settings") else ("连续按原路自动推进并确认已审核的送物交易；普通随机遇敌沿用自动战斗，成功后继续。缺物、需手动选择或战斗失败等停止时，处理后请再次点击自动推进。" if strict else "便利导航模式：使用任务便捷传送并确认原交易，不是连续原路行走。"))+"关窗、Esc 或最小化后继续，点击停止可中止。",12)
	if source_job:
		label(content,"金布伊原路自动：请先自行到合资格的原大厅，或处于已有真实到达资格的运行路线；此金布伊任务路径不会自动送往大厅、购票或刷物。自动模式查原公开题目答案是项目便利；猜拳沿用原随机规则和合法重试，不保证获胜，缺票即停止。按原流程自动领取会员证并兑换唯一 Lv1 金布伊，此任务无需每次手选奖励。",12).name="QuestAutoSourceDetails"
		label(content,"本任务实际执行 %s（正常原路）；已保存的 B/C 偏好保留给其他支持任务，不改变全局偏好。"%str(source_entry.get("effective_mode","A")),12).name="QuestAutoSourceMode"
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

func present_auto_settings()->void:
	if not is_instance_valid(settings_panel):return
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	var settings:Dictionary=auto.get("settings",{})
	var index:int=["A","B","C"].find(str(settings.get("mode","A")))
	var reason:=settings_feedback
	if reason.is_empty():
		reason="模式在安全路段边界应用。" if auto.has("settings") else "当前服务尚未提供自动任务设置。"
	if auto.has("settings"):
		reason+="\n已保存移动意图：%s；当前实际执行：%s。"%[str(settings.get("mode","A")),str(auto.get("effective_mode","A"))]
		reason+="\n当前可执行模式：%s。%s"%[", ".join(auto.get("available_modes",["A"])),str(auto.get("mode_notice",""))]
	if selected_id==2:
		var source_entry:Dictionary=auto.get("source_entry",{})
		reason+="\n金布伊任务实际执行 %s（正常原路）；B/C 可作为其他支持任务的偏好保存。"%str(source_entry.get("effective_mode","A"))
	settings_panel.present(maxi(index,0),int(settings.get("loot_minutes",30)),[0,1,2],auto.has("settings") and not settings_pending and (world.link.is_local() or world.link.online),reason)

func save_auto_settings(mode_index:int,minutes:int)->void:
	if settings_pending or not (world.link.is_local() or world.link.online):return
	settings_pending=true
	settings_feedback="正在保存设置…"
	present_auto_settings()
	world.link.request({"type":"set_automation_settings","settings":{"quest":{"mode":["A","B","C"][mode_index],"loot_minutes":minutes}}},func(reply:Dictionary):
		settings_pending=false
		settings_feedback="设置已保存；实际执行模式以任务状态为准。" if reply.get("ok",false) else str(reply.get("reason","设置保存失败。"))
		present_auto_settings())
