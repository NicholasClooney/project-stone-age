extends PanelContainer
## Snapshot-only background control; never owns the task or its lifetime.
const AutomationChip=preload("res://scripts/automation_chip.gd")
var world:Node
var restore_button:Button
var stop_button:Button
var loot_panel:PanelContainer
func configure(owner:Node) -> void:
	world=owner
	name="QuestAutoChip"
	z_index=60
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",world.box(Color("20292f",0.96),Color("b29b65")))
	var column:=VBoxContainer.new()
	add_child(column)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	column.add_child(row)
	restore_button=world.button("",restore)
	restore_button.name="QuestAutoRestore"
	restore_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	restore_button.custom_minimum_size=Vector2(0,58)
	restore_button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	restore_button.clip_text=true
	restore_button.add_theme_font_size_override("font_size",14)
	row.add_child(restore_button)
	stop_button=world.button("停止",func():world.quest_helper_travel.cancel())
	stop_button.name="QuestAutoChipStop"
	stop_button.custom_minimum_size=Vector2(64,44)
	row.add_child(stop_button)
	loot_panel=preload("res://scripts/quest_auto_loot_panel.gd").new()
	column.add_child(loot_panel)
	loot_panel.hide()
	hide()
func restore() -> void:
	world.quest_helper_menu.settings_open=false
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	if auto.get("running",false) or str(auto.get("phase",""))=="manual":
		world.quest_helper_menu.selected_id=int(auto.get("quest_id",-1))
		world.quest_helper_menu.detail_open=true
	world.quest_helper_menu.open_menu()
func _process(_delta:float) -> void:
	var auto:Dictionary=world.state.derived.get("quest_auto",{})
	var manual:bool=not auto.get("running",false) and str(auto.get("phase",""))=="manual"
	var budget:Dictionary=auto.get("budget",{})
	var loot_enabled:bool=world.state.quest_loot_enabled()
	var recovery_locked:bool=budget.get("recovery_blocked",false)==true
	var history:bool=budget.get("entry",null) is Dictionary or recovery_locked
	var shown:bool=not world.quest_helper_menu.visible and (auto.get("running",false) or manual or world.quest_helper_travel.auto_pending() or recovery_locked or (loot_enabled and history))
	if shown and not visible:move_to_front()
	visible=shown
	if not visible:return
	var step:String=world.quest_helper_travel.auto_status(not (loot_enabled and not budget.is_empty()))
	var heading:String=world.quest_helper_travel.auto_heading()
	if world.quest_helper_travel.auto_pending():heading="自动任务准备中"
	elif history and not auto.get("running",false) and not manual:heading="任务预算记录"
	loot_panel.visible=loot_enabled and not budget.is_empty()
	if loot_panel.visible:loot_panel.present_snapshot(auto,not world.link.is_local() and not world.link.online)
	restore_button.text=heading+"\n"+step
	stop_button.visible=not manual and (auto.get("running",false) or world.quest_helper_travel.auto_pending())
	restore_button.tooltip_text=step+"\n点击重开任务助手"
	stop_button.disabled=not (world.link.is_local() or world.link.online)
	var screen:Vector2=world.get_viewport_rect().size
	size=Vector2(minf(420,screen.x-24),230 if loot_panel.visible else 70)
	var bottom:=screen.y-50
	# Existing automation bars occupy slot 0 (and may be taller than 58px).
	for sibling in get_parent().get_children():
		if sibling.get_script()==AutomationChip and sibling.visible:bottom=minf(bottom,sibling.position.y-6)
	position=Vector2(screen.x-size.x-12,maxf(8,bottom-size.y))
