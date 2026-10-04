extends SceneTree
## Isolated layout and input contract, not a server/schema/route verification.
const Settings=preload("res://scripts/quest_auto_settings.gd")
const Wait=preload("res://tests/support/wait.gd")
var submitted:Array=[]
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	if not value:push_error(message);quit(1)
	return value
func run()->void:
	root.content_scale_size=Vector2i.ZERO
	for dimensions in [Vector2i(390,844),Vector2i(1280,720)]:
		root.size=dimensions
		var panel:=PanelContainer.new()
		panel.position=Vector2(12,12)
		panel.size=Vector2(mini(600,dimensions.x-24),dimensions.y-24)
		root.add_child(panel)
		var scroller:=ScrollContainer.new()
		scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroller)
		var settings=Settings.new()
		scroller.add_child(settings)
		settings.apply_requested.connect(func(mode_index:int,minutes:int):submitted.append([mode_index,minutes]))
		settings.present(0,30,[0],true)
		if not check(await Wait.until(self,func():return settings.size.x>0 and settings.description.size.y>0 and scroller.size.x>0 and settings.size.x<=scroller.size.x and root.get_visible_rect().encloses(panel.get_global_rect())),"Settings containers settle"):return
		if not check(settings.size.x<=scroller.size.x and root.get_visible_rect().encloses(panel.get_global_rect()),"Settings fit narrow and wide viewport"):return
		if not check(settings.mode.selected==0 and settings.budget.value==30 and settings.mode.is_item_disabled(1) and settings.mode.is_item_disabled(2),"A default; unavailable executors disabled by caller"):return
		settings.apply_button.pressed.emit()
		if not check(submitted.back()==[0,30],"Apply emits explicit user intent only"):return
		settings.present(2,180,[0,1,2],true)
		if not check(settings.description.text.contains("单位时间遇敌更多") and settings.description.text.contains("项目改动"),"C exposes encounter and project-change semantics"):return
		settings.budget.value=0
		if not check(settings.budget.value==1,"No unlimited zero budget"):return
		settings.budget.value=181
		if not check(settings.budget.value==180,"Budget capped at 180 minutes"):return
		var count:=submitted.size()
		settings.present(1,30,[0,1,2],false,"等待服务确认")
		settings.apply_button.pressed.emit()
		if not check(submitted.size()==count and settings.mode.disabled and not settings.budget.editable and settings.feedback.text=="等待服务确认","Read-only/pending state cannot submit"):return
		var pending_free:WeakRef=weakref(panel)
		panel.queue_free()
		if not check(await Wait.until(self,func():return pending_free.get_ref()==null),"Layout disposed"):return
	print("QUEST AUTO V2 SETTINGS UI: PASS")
	quit(0)
