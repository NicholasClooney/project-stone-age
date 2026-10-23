extends SceneTree
## Synthetic protocol replies verify presentation and lifecycle, not settlement.
const View=preload("res://scripts/quick_transmigration_menu.gd")
const State=preload("res://network/client_state.gd")
const Wait=preload("res://tests/support/wait.gd")
class Link extends RefCounted:
	signal disconnected
	var sent: Array=[]
	var callbacks: Array=[]
	func request(command: Dictionary, done: Callable=Callable()) -> Dictionary:
		sent.append(command.duplicate(true));callbacks.append(done);return {"pending":true}
	func answer(index: int, value: Dictionary) -> void:
		var done: Callable=callbacks[index];callbacks[index]=Callable()
		if done.is_valid():done.call(value)
class Session extends RefCounted:
	var state
	func snapshot() -> Dictionary:return state.full_profile()
class World extends Control:
	var link=Link.new()
	var state=State.new()
	var session=Session.new()
	var message=Label.new()
var failures:=0
var world: World
func _initialize() -> void:call_deferred("run")
func check(value: bool, note: String) -> void:
	print(("PASS: " if value else "FAIL: ")+note)
	if not value:failures+=1
func preview(token: String="one") -> Dictionary:
	return {"ok":true,"quick_transmigration":{"token":token,"new_count":1,"level_mode":"120","actual_level":80,"target_level":120,"existing_points":37,"gained_points":120,"allocation":[{"stat":"strength","points":157}],"pre_base_stats":{"vitality":900,"strength":36400,"toughness":0,"dexterity":400},"base_stats":{"vitality":1234,"strength":2345,"toughness":3456,"dexterity":4567},"stat_points":10,"quest_count":20,"equation":1310840,"reward":{"enemy_id":777,"template_id":25,"name":"奖励甲"},"location":{"map_id":1000,"x":80,"y":90},"warning":"服务器核验"}}
func open_view():
	var view=View.new();world.add_child(view);view.setup(world)
	view.dismissed.connect(func():view.shutdown();view.queue_free())
	return view
func click(button: Control) -> void:
	await Wait.until(self,func():return button.size.y>=44)
	var point:=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	check(root.gui_get_hovered_control()==button,"button reachable: "+button.text)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func text_of(node: Node) -> String:
	var result: String=node.text if node is Label else ""
	for child in node.get_children():result+="\n"+text_of(child)
	return result
func run() -> void:
	root.unfocusable=true;root.position=Vector2i(-10000,-10000);root.content_scale_size=Vector2i.ZERO
	for viewport in [Vector2i(1280,900),Vector2i(390,844)]:
		root.size=viewport
		world=World.new();root.add_child(world);world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		world.session.state=world.state;world.state.profile={"player":{"level":80,"transmigration":0},"pets":[]}
		world.add_child(world.message)
		var view=open_view();await process_frame
		check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(view.card.get_global_rect()),"card fits "+str(viewport))
		check(view.modes.selected==1 and view.bonus.button_pressed and view.selected_stats().size()==4,"defaults 120 / 20 / four stats")
		check(view.confirm.disabled,"no confirmation before preview")
		await click(view.refresh)
		check(world.link.sent[-1]=={"type":"quick_transmigration","action":"preview","level_mode":"120","bonus_quests":20,"allocation_stats":["vitality","strength","toughness","dexterity"]},"preview sends options only")
		var pending: int=world.link.sent.size()-1
		view._request_preview();check(world.link.sent.size()==pending+1,"duplicate preview blocked")
		world.link.answer(pending,preview())
		var detail:=text_of(view.details)
		check(detail.contains("旧未配点 37") and detail.contains("模拟新增点 120") and detail.contains("腕力 157") and detail.contains("体力 12.34") and detail.contains("奖励甲") and detail.contains("END69"),"authority numbers, fixed-point scale, reward and reset details shown")
		await click(view.confirm)
		check(world.link.sent[-1]=={"type":"quick_transmigration","action":"confirm","token":"one"},"confirmation token only")
		pending=world.link.sent.size()-1;view._confirm();check(world.link.sent.size()==pending+1,"duplicate confirmation blocked")
		world.link.answer(pending,{"ok":false,"reason":"另一设备已使用此token"})
		check(view.stale and view.confirm.disabled and view.status.text.contains("另一设备"),"server invalidation visible and cannot replay")
		await click(view.refresh);pending=world.link.sent.size()-1
		world.state.profile.player.level=81;world.state.changed.emit("profile")
		world.link.answer(pending,preview("changed"))
		check(view.stale and view.confirm.disabled,"state changing during preview cannot become fresh")
		await click(view.refresh);world.link.answer(world.link.sent.size()-1,preview("fresh"))
		check(not view.confirm.disabled,"fresh preview accepted")
		world.state.profile.player.gold=20;world.state.changed.emit("snapshot")
		check(view.stale and view.confirm.disabled,"other-device profile change invalidates preview")
		view.bonus.button_pressed=false
		view.modes.select(2);view._options_changed()
		await click(view.refresh)
		check(world.link.sent[-1].level_mode=="130" and world.link.sent[-1].bonus_quests==0,"130 and zero bonus independently selectable")
		world.link.answer(world.link.sent.size()-1,{"ok":false,"reason":"随身宠物已满"})
		check(view.status.text.contains("随身宠物已满"),"server capacity reason displayed")
		for choice in view.selectors:choice.button_pressed=false
		check(view.refresh.disabled and view.eligibility.text.contains("至少"),"empty allocation blocked")
		view.selectors[1].button_pressed=true
		check(view.selected_stats()==["strength"] and not view.refresh.disabled,"single stat allocation supported")
		world.state.profile.player.level=1;world.state.changed.emit("profile")
		view.modes.select(0);view._options_changed()
		check(view.refresh.disabled and view.eligibility.text.contains("120或130") and view.modes.is_item_disabled(0),"current below80 explicitly disabled")
		world.state.profile.player.level=125;view.modes.select(1);view._options_changed()
		check(view.refresh.disabled and view.eligibility.text.contains("低于真实等级") and view.modes.is_item_disabled(1),"target below actual blocked with explanation")
		world.state.profile.player.transmigration=5;view._options_changed()
		check(view.refresh.disabled and view.eligibility.text.contains("五转"),"five-turn cap visible")
		world.state.profile.player={"level":80,"transmigration":0};view.modes.select(1);view._options_changed()
		await click(view.refresh);world.link.answer(world.link.sent.size()-1,preview("cancel"))
		await click(view.cancel)
		check(world.link.sent[-1]=={"type":"quick_transmigration","action":"cancel","token":"cancel"},"cancel releases exact token")
		# Late replies for two views may reuse a token in either order.
		for reverse in [false,true]:
			view=open_view();view._request_preview();var old: int=world.link.sent.size()-1
			view.shutdown();view.queue_free();view=open_view();view._request_preview();var newest: int=world.link.sent.size()-1
			world.link.answer(newest if reverse else old,preview("shared"))
			world.link.answer(old if reverse else newest,preview("shared"))
			check(view.token=="shared" and world.link.sent.size()==newest+1,"late old reply does not cancel reused token "+str(reverse))
			view.shutdown();view.queue_free()
		view=open_view();view._request_preview();world.link.answer(world.link.sent.size()-1,preview("done"))
		view._confirm();world.link.answer(world.link.sent.size()-1,{"ok":true,"closed":true,"new_count":1,"location":{},"transaction_id":"fixture"})
		check(not view.live and world.message.text.contains("Lv1"),"success closes, no automatic next turn")
		view=open_view();view._request_preview();var orphan: int=world.link.sent.size()-1
		var held=world.link;world.queue_free();await process_frame
		held.answer(orphan,preview("orphan"))
		check(held.sent[-1]=={"type":"quick_transmigration","action":"cancel","token":"orphan"},"freed world releases late preview")
	check(View.deliveries.is_empty(),"lifecycle registry fully released")
	print("QUICK TRANSMIGRATION UI: %d failures" % failures)
	quit(1 if failures else 0)
