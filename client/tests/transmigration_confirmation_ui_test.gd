extends SceneTree
## Synthetic server replies exercise UI lifecycle only; no route/settlement claim.
const View=preload("res://scripts/transmigration_confirmation.gd")
const Dialogue=preload("res://scripts/quest_dialogue.gd")
const State=preload("res://network/client_state.gd")
const Wait=preload("res://tests/support/wait.gd")
class Link extends RefCounted:
	signal disconnected
	var sent: Array=[]
	var callbacks: Array=[]
	func request(command: Dictionary, done: Callable=Callable()) -> Dictionary:
		sent.append(command.duplicate(true));callbacks.append(done)
		return {"pending":true}
	func answer(index: int, value: Dictionary) -> void:
		var done: Callable=callbacks[index]
		callbacks[index]=Callable()
		if done.is_valid():done.call(value)
class Session extends RefCounted:
	var state
	func snapshot() -> Dictionary:return state.full_profile()
class World extends Control:
	var link=Link.new()
	var state=State.new()
	var session=Session.new()
	var data={"map_id":32021}
	var cell=Vector2i(31,27)
	var moving=false
	var paused_input=false
	var world_travel
	var dialogue=Control.new()
	var battle_view=Control.new()
	var message=Label.new()
	func clear_input() -> void:pass
	func _panel_open() -> bool:return false
	func automation_minimized() -> bool:return false
var failures:=0
var world: World
var controller
var overlay: Control
func _initialize() -> void:call_deferred("run")
func check(value: bool, note: String) -> void:
	print(("PASS: " if value else "FAIL: ")+note)
	if not value:failures+=1
func preview(token: String="one") -> Dictionary:
	return {"ok":true,"transmigration":{"token":token,"npc_id":View.NPC_ID,"new_count":1,"quest_count":4,"base_stats":{"vitality":1234,"strength":2345,"toughness":3456,"dexterity":4567},"stat_points":10,"sacrifices":[{"pet_id":"pet-a","template_id":693,"name":"祭品甲","level":80}],"reward":{"enemy_id":777,"template_id":25},"location":{"map_id":1000,"x":80,"y":90},"warning":"服务器核验；不会显示奖励随机成长。"}}
func build() -> void:
	world=World.new();root.add_child(world);world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.session.state=world.state
	world.state.profile={"player":{"transmigration":0},"pets":[{"pet_id":"pet-a","species":"original_693","name":"祭品甲","level":80},{"pet_id":"pet-b","species":"original_693","name":"祭品乙","level":2},{"pet_id":"wrong","species":"original_694","name":"异模板","level":80}]}
	world.state.pet_storage=[{"pet_id":"stored","species":"original_693","name":"仓库同种","level":90}]
	world.dialogue.hide();world.battle_view.hide()
	world.add_child(world.dialogue);world.add_child(world.battle_view);world.add_child(world.message)
	overlay=Control.new();world.add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=Control.new();overlay.add_child(panel)
	var scroll:=ScrollContainer.new();panel.add_child(scroll)
	var body:=Label.new();scroll.add_child(body)
	controller=Dialogue.new();world.add_child(controller);controller.setup(world,overlay,body)
func click(button: Control) -> void:
	await Wait.until(self,func():return button.size.y>=44)
	var point:=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	await process_frame
	check(root.gui_get_hovered_control()==button,"visible button is actual hover target: "+str(button.name))
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
	await process_frame
func proof(view, label: String, viewport: Vector2i) -> void:
	var path:=OS.get_environment("STONE_AGE_PROOF_DIR")
	if path.is_empty():return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path+"/%d-%s.png" % [viewport.x,label])
func run() -> void:
	root.unfocusable=true;root.position=Vector2i(-10000,-10000)
	root.content_scale_size=Vector2i.ZERO
	for viewport in [Vector2i(1280,900),Vector2i(390,844)]:
		root.size=viewport;build()
		controller.open(View.NPC_ID);world.link.answer(0,preview())
		var view=controller.confirmation
		await process_frame
		check(view.live and view.token=="one","exact king top-level preview opens")
		check(view.selectors.size()==2,"only carried matching templates selectable; no pet storage")
		check(view.selected_ids==["pet-a"],"authority default UID retained in original slot order")
		check(Rect2(Vector2.ZERO,Vector2(viewport)).encloses(view.card.get_global_rect()),"confirmation fits viewport "+str(viewport))
		await proof(view,"preview",viewport)
		await click(view.confirm)
		check(world.link.sent[-1]=={"type":"transmigration","action":"confirm","token":"one"},"confirm sends token only")
		check(view.confirm.disabled,"in-flight confirmation cannot duplicate")
		world.link.answer(world.link.sent.size()-1,{"ok":false,"reason":"save_failed"})
		check(view.token=="one" and not view.confirm.disabled and view.status.text.contains("保存失败"),"save rejection retains same token retry with visible reason")
		await proof(view,"save-rejected",viewport)
		world.state.profile.player.gold=20;world.state.changed.emit("profile")
		check(view.confirm.disabled and view.stale,"other-device profile update invalidates visible preview")
		await proof(view,"stale",viewport)
		await click(view.refresh)
		check(world.link.sent[-1].action=="preview" and world.link.sent[-1].pet_ids==["pet-a"],"refresh submits exact selected UID without computed values")
		world.link.answer(world.link.sent.size()-1,preview("two"))
		check(view.token=="two" and not view.confirm.disabled,"fresh authority preview enables confirmation")
		await click(view.cancel)
		check(not controller.active and world.link.sent[-1]=={"type":"transmigration","action":"cancel","token":"two"},"real cancel click closes and cancels exact token")
		controller.open(View.NPC_ID);world.link.answer(world.link.sent.size()-1,preview("select"))
		view=controller.confirmation
		await Wait.until(self,func():view.scroll.ensure_control_visible(view.selectors[1]);return view.scroll.get_global_rect().encloses(view.selectors[1].get_global_rect()))
		await click(view.selectors[1])
		check(view.selected_ids==["pet-b"] and view.confirm.disabled,"real selection chooses distinct same-template UID and requires fresh preview")
		await click(view.refresh)
		check(world.link.sent[-1].pet_ids==["pet-b"],"selected low-level same-template pet is submitted without invented level restriction")
		var chosen:=preview("selected");chosen.transmigration.sacrifices[0]={"pet_id":"pet-b","template_id":693,"name":"祭品乙","level":2}
		world.link.answer(world.link.sent.size()-1,chosen)
		await click(view.confirm)
		world.link.answer(world.link.sent.size()-1,{"ok":true,"transaction_id":"fixture-only","new_count":1,"location":{},"closed":true})
		check(not controller.active,"successful protocol reply closes UI; synthetic reply is not a settlement test")
		# Two delayed opens reusing one server token must not cancel the live view.
		controller.open(View.NPC_ID);var old: int=world.link.sent.size()-1
		controller.close();controller.open(View.NPC_ID);var newest: int=world.link.sent.size()-1
		world.link.answer(old,preview("shared"))
		check(world.link.sent.size()==newest+1,"old reply cleanup waits for newer in-flight preview")
		world.link.answer(newest,preview("shared"))
		check(controller.confirmation.token=="shared" and world.link.sent.size()==newest+1,"late old reply cannot cancel reused live token")
		controller.close()
		check(world.link.sent[-1].token=="shared","closing newest owner cancels shared token once")
		controller.open(View.NPC_ID);old=world.link.sent.size()-1
		controller.close();controller.open(View.NPC_ID);newest=world.link.sent.size()-1
		world.link.answer(newest,preview("new-first"));world.link.answer(old,preview("new-first"))
		check(controller.confirmation.token=="new-first" and world.link.sent.size()==newest+1,"reverse reply ordering also protects the live token")
		controller.close()
		controller.open(View.NPC_ID);old=world.link.sent.size()-1
		controller.open("some-other-npc");newest=world.link.sent.size()-1
		world.link.answer(old,preview("old-king"))
		check(world.link.sent[-1]=={"type":"transmigration","action":"cancel","token":"old-king"} and not is_instance_valid(controller.confirmation),"changing NPC cleans late king preview without opening it")
		world.link.answer(newest,{"ok":false,"reason":"关闭"})
		controller.close()
		# World disappears before a preview reply.
		controller.open(View.NPC_ID);var orphan: int=world.link.sent.size()-1
		var held=world.link;world.queue_free();await process_frame
		held.answer(orphan,preview("orphan"))
		check(held.sent[-1]=={"type":"transmigration","action":"cancel","token":"orphan"},"freed world late preview cancels only its token")
	check(View.deliveries.is_empty(),"all preview lifecycle bookkeeping released")
	print("TRANSMIGRATION CONFIRMATION UI: %d failures" % failures)
	quit(1 if failures else 0)
