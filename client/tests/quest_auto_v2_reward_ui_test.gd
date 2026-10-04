extends SceneTree
## Synthetic transport and public snapshots. No quest transaction/route claim.
const Wait=preload("res://tests/support/wait.gd")
const Dialogue=preload("res://scripts/quest_dialogue.gd")
class Link extends RefCounted:
	signal disconnected
	var commands:Array=[]
	var replies:Array[Callable]=[]
	func request(command:Dictionary,done:Callable=Callable())->void:
		commands.append(command.duplicate(true))
		if done.is_valid():replies.append(done)
class World extends Node:
	var link=Link.new()
	var state:Dictionary={"derived":{}}
	var data:Dictionary={"map_id":100}
	var cell:=Vector2i.ZERO
	var moving:=false
	var paused_input:=false
	var world_travel:Node
	var dialogue:=Control.new()
	var battle_view:=Control.new()
	var message:=Label.new()
	func _init()->void:
		add_child(dialogue);dialogue.hide();add_child(battle_view);battle_view.hide();add_child(message)
	func clear_input()->void:pass
	func _panel_open()->bool:return false
	func automation_minimized()->bool:return false
var world:World
var controller
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	if not value:push_error(message);quit(1)
	return value
func waiting(revision:int,token:String="same-token")->Dictionary:
	return {"running":true,"phase":"waiting_reward","run_id":"run-one","step_id":"reward-one","revision":revision,"waiting":{"kind":"reward","npc_id":"reward-npc","token":token,"dialogue":{"token":token,"npc_id":"reward-npc","name":"奖励","text":"请手动选择","choices":[{"id":"first","text":"奖励一"},{"id":"second","text":"奖励二"},{"id":"third","text":"奖励三：较长的奖励说明应自动换行"}]}}}
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	world=World.new();root.add_child(world)
	var overlay:=Control.new();world.add_child(overlay)
	var panel:=Panel.new();panel.position=Vector2(3,300);panel.size=Vector2(384,210);overlay.add_child(panel)
	var scroll:=ScrollContainer.new();panel.add_child(scroll)
	var text:=Label.new();scroll.add_child(text)
	controller=Dialogue.new();world.add_child(controller);controller.setup(world,overlay,text)
	world.state.derived.quest_auto=waiting(1)
	controller.open_auto(waiting(0))
	if not check(not controller.active,"Cached old wait cannot reopen a window"):return
	controller.open_auto(world.state.derived.quest_auto)
	if not check(controller.active and world.link.commands.is_empty(),"Opening public waiting dialogue never sends quest_talk"):return
	if not check(await Wait.until(self,func():return controller.buttons[2].size.y>=44 and controller.buttons[2].size.x>0 and controller.buttons[2].position.y>controller.buttons[1].position.y),"Reward buttons settle"):return
	if not check(controller.buttons[2].position.y>controller.buttons[1].position.y and controller.buttons[2].size.x<=controller.service_scroll.size.x,"Three rewards stack within narrow scroll instead of overflowing horizontally"):return
	var old_button:Button=controller.buttons[0]
	world.state.derived.quest_auto=waiting(2)
	old_button.pressed.emit()
	if not check(world.link.commands.is_empty() and not controller.active,"Old button cannot use newer revision even with same token"):return
	controller.open_auto(world.state.derived.quest_auto)
	old_button=controller.buttons[0]
	world.state.derived.quest_auto=waiting(3)
	controller._process(0)
	old_button.pressed.emit()
	if not check(controller.active and controller.auto_identity.quest_revision==3 and world.link.commands.is_empty(),"New stage rebuilds; old rendered callback cannot submit"):return
	controller.choose("second")
	if not check(world.link.commands.size()==1 and world.link.commands[0].quest_revision==3 and world.link.commands[0].choice=="second" and world.link.commands[0].token=="same-token","Actual click sends frozen capability"):return
	var late:Callable=world.link.replies.pop_front()
	world.state.derived.quest_auto=waiting(4)
	controller._process(0)
	late.call({"ok":true,"closed":true,"dialogue":{"token":"same-token"}})
	if not check(controller.active and controller.auto_identity.quest_revision==4 and world.link.commands.size()==1,"Late ack never closes replacement same-token window"):return
	world.state.derived.quest_auto={"running":false,"phase":"manual"}
	controller._process(0)
	if not check(not controller.active and world.link.commands.size()==1,"Other-device stop removes window without closing a newer pending"):return
	world.state.derived.quest_auto=waiting(5)
	controller.open_auto(world.state.derived.quest_auto)
	controller.close()
	if not check(world.link.commands.size()==2 and world.link.commands.back().type=="quest_close" and world.link.commands.back().quest_revision==5,"User close carries only its frozen identity"):return
	world.state.derived.quest_auto=waiting(6)
	controller.open_auto(world.state.derived.quest_auto)
	controller.choose("first")
	late=world.link.replies.pop_front()
	controller.free()
	var count:int=world.link.commands.size()
	late.call({"ok":true,"dialogue":{"token":"same-token"}})
	if not check(world.link.commands.size()==count,"Destroyed receiver never closes a token from delayed automatic reward ack"):return
	world.queue_free()
	print("QUEST AUTO V2 REWARD UI SYNTHETIC: PASS")
	quit(0)
