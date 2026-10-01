extends PanelContainer
## Read-only view of the server's original quest progress.
var world: Node
var body: VBoxContainer
var last_model := ""
func configure(owner: Node) -> void:
	world=owner
	name="QuestHelperMenu"
	z_index=60
	custom_minimum_size=Vector2(720,0)
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
	world.quest_helper_travel.cancel()
	hide()
	world.paused_input=world.battle_view.visible or world.automation_minimized()
	world.clear_input()
func relayout() -> void:
	reset_size()
	position=((world.get_viewport_rect().size-size)/2).max(Vector2(8,8))
func model() -> Dictionary:
	return world.state.derived.get("quest_helper",{})
func _process(_delta: float) -> void:
	if visible and JSON.stringify([model(),world.state.derived.get("quest_auto",{})])!=last_model:rebuild()
func rebuild() -> void:
	last_model=JSON.stringify([model(),world.state.derived.get("quest_auto",{})])
	for child in get_children():remove_child(child);child.queue_free()
	body=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	add_child(body)
	var header:=HBoxContainer.new()
	body.add_child(header)
	var title: Label=world.text("任务助手",20)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button=world.button("关闭 · Esc",close_menu)
	close.name="QuestHelperClose"
	header.add_child(close)
	body.add_child(world.text("本项目助手：贝壳可自动确认原交易；按停止、关闭或 Esc 可停止。",12))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size=Vector2(690,430)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list:=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",10)
	scroll.add_child(list)
	for quest in model().get("quests",[]):
		var label: Label=world.text(str(quest.title)+" · "+str(quest.status),18)
		label.name="QuestHelper_%s" % str(quest.id)
		list.add_child(label)
		if not str(quest.get("blocked_reason","")).is_empty():list.add_child(world.text(str(quest.blocked_reason),12))
		if not str(quest.get("completion_detail","")).is_empty():list.add_child(world.text(str(quest.completion_detail),12))
		if bool(quest.get("can_restart",false)):list.add_child(world.text("可重做：请与原 NPC 对话确认。",12))
		if int(quest.event)==2:
			var auto:Dictionary=world.state.derived.get("quest_auto",{})
			var running:bool=bool(auto.get("running",false))
			var action:Button=world.button("停止自动任务" if running else ("自动重做贝壳任务" if quest.get("can_restart",false) else "自动完成贝壳任务"),func():
				if running:world.quest_helper_travel.cancel()
				else:world.quest_helper_travel.start_auto(int(quest.id)))
			action.name="QuestAutoStop" if running else "QuestAutoStart_%s" % quest.id
			action.disabled=not running and ((str(quest.status)=="已完成" and not quest.get("can_restart",false)) or not str(quest.get("blocked_reason","")).is_empty())
			list.add_child(action)
			if not str(auto.get("message","")).is_empty():list.add_child(world.text(str(auto.message),12))
		for step in quest.get("steps",[]):
			var row:=HBoxContainer.new()
			list.add_child(row)
			var caption: Label=world.text(("▶ " if step.get("current",false) else ("✓ " if step.get("done",false) else "· "))+str(step.label),14)
			caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			if step.get("current",false):caption.add_theme_color_override("font_color",Color("ffe680"))
			row.add_child(caption)
			if int(step.get("map_id",-1))<0 or step.get("cell",[]).size()!=2:continue
			for mode in ["near","arrival"]:
				var target: Dictionary=step.duplicate(true)
				target.quest_id=int(quest.id)
				var visit: Button=world.button("瞬移" if mode=="near" else "瞬移到该地图并走过去",func():
					# Hide without cancelling the newly requested journey.
					hide()
					world.paused_input=false
					world.quest_helper_travel.visit(target,mode))
				visit.name=("QuestVisit_%s_%s_%s" % [quest.id,step.id,mode]).validate_node_name()
				visit.set_meta("quest_step",target)
				visit.set_meta("visit_mode",mode)
				row.add_child(visit)
	relayout()
