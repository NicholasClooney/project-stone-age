extends "res://tests/quest_auto_background_ui_test.gd"
## Real original shell REQUEST/ACCEPT transactions and two WS connections.
## Public NPC placement and runner wait invocation are fixtures, not route proof.
var other
var pump
func capability(choice:String)->Dictionary:
	var auto:Dictionary=world.state.derived.quest_auto
	return {"type":"quest_choose","quest_run_id":auto.run_id,"quest_step_id":auto.step_id,"quest_revision":auto.revision,"token":auto.waiting.token,"choice":choice}
func prepare_wait(reset:bool)->bool:
	if reset:
		backend_node.quest_auto.stop(backend_node)
		Rules.set_flag(backend_node.session._profile,"now",2,false)
		Rules.set_flag(backend_node.session._profile,"ended",2,false)
		backend_node.session._profile.original_items=[]
	backend_node.quest_auto.quest_id=11
	var step:Dictionary=backend_node.quest_auto.strict_select(backend_node).get("step",{})
	if not check(not step.is_empty(),"Real shell plan supplies next original transaction"):return false
	var npc:Dictionary=backend_node.original_quests.npc_by_id(step.npc_id)
	var point:Dictionary=backend_node.quest_helper.geometric_destination(backend_node,npc,"near")
	backend_node.automation.position_changed(point.map_id,Vector2i(point.cell[0],point.cell[1]))
	if reset:
		if not check(backend_node.handle({"type":"quest_auto_start","quest_id":11,"client":"fixture"}).ok,"Start strict runner for actual shell transaction"):return false
	backend_node.quest_auto.identity.select_step(str(step.id))
	backend_node.quest_auto.internal=true
	var reply:Dictionary=backend_node.original_quests.talk(backend_node,str(npc.id))
	backend_node.quest_auto.internal=false
	backend_node.quest_auto.wait_reward(backend_node,reply)
	# Fixture placement is not an automation move issued during reward wait.
	backend_node.emit_event({"type":"position","map_id":point.map_id,"cell":point.cell.duplicate(),"client":"fixture"})
	return check(backend_node.quest_auto.phase=="waiting_reward","Real original dialogue is waiting")
func sync_wait()->bool:
	if not check(await Wait.settle(self,world),"Reward snapshot settles"):return false
	return await ready(func():return int(world.data.map_id)==backend_node.automation.position_map and world.cell==backend_node.automation.position_cell and not world.area_transition_busy,"Client loads authority reward location")
func open_reward()->bool:
	world.quest_helper_menu.open_menu()
	if not await click(world.quest_helper_menu.find_child("QuestAutoReward",true,false)):return false
	return await ready(func():return world.world_travel.quest_dialogue.active,"Real reward action opens snapshot dialogue")
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	remote_mode=true
	backend_node=Backend.new();backend_node.set_process(false)
	backend_node.session._profile.original_savepoint_bits=1
	backend_node.session._profile.no_random_encounters=true
	backend_node.save_path="user://quest-auto-v2-reward-remote.json"
	if not prepare_wait(true):return
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Reward server port0"):return
	if not await create_world():return
	pump=LinkPump.new();root.add_child(pump)
	other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port);pump.links=[other];other.connect_now()
	if not await ready(func():return other.online,"Second authenticated reward device connects"):return
	if not await sync_wait() or not await open_reward():return
	var old:Dictionary=capability("yes")
	if not await click(world.world_travel.quest_dialogue.buttons[0]):return
	if not check(await Wait.settle(self,world),"REQUEST save roundtrip"):return
	if not await ready(func():return not world.world_travel.quest_dialogue.active,"Saved request closes UI without extra acknowledgement"):return
	if not check(backend_node.quest_auto.phase=="travel" and Rules.flag(backend_node.session._profile,"now",2),"Saved real REQUEST automatically continues"):return
	if not check(not (await rpc(other,old)).ok,"Other device cannot replay saved request capability"):return
	if not prepare_wait(false) or not await sync_wait():return
	# A freshly created client discovers the public wait without re-talking.
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"First client disposed before opening next window"):return
	if not await create_world() or not await sync_wait() or not await open_reward():return
	old=capability("yes")
	var saved_serial:int=backend_node.quest_save_serial
	if not await click(world.world_travel.quest_dialogue.buttons[0]):return
	if not check(await Wait.settle(self,world),"ACCEPT confirmation roundtrip"):return
	if not await ready(func():return world.world_travel.quest_dialogue.active and world.world_travel.quest_dialogue.auto_identity.quest_revision!=old.quest_revision,"New revision rebuilds original confirmation"):return
	if not check(backend_node.quest_auto.phase=="waiting_reward" and backend_node.quest_save_serial==saved_serial and not Rules.flag(backend_node.session._profile,"ended",2),"Unsaved confirmation is never treated as success"):return
	if not check(not (await rpc(other,old)).ok and backend_node.quest_auto.running,"Old revision rejection preserves new wait"):return
	var final_choice:=capability("ok")
	# Second real socket can commit this character's current displayed capability.
	if not check((await rpc(other,final_choice)).ok,"Second device chooses current reward confirmation"):return
	if not check(await Wait.settle(self,world),"Final saved reward publishes to first UI"):return
	if not await ready(func():return not world.world_travel.quest_dialogue.active,"Other-device reward completion closes obsolete window"):return
	if not check(not backend_node.quest_auto.running and Rules.flag(backend_node.session._profile,"ended",2),"Final original reward completes exactly once"):return
	if not check(not (await rpc(other,final_choice)).ok,"Final reward cannot replay"):return
	for failure in ["stop","close","savefail"]:
		if not prepare_wait(true) or not await sync_wait() or not await open_reward():return
		old=capability("yes")
		if failure=="stop":
			if not check((await rpc(other,{"type":"quest_auto_stop"})).ok,"Other device cancels wait"):return
		elif failure=="close":world.world_travel.quest_dialogue.close()
		else:
			backend_node.save_path="user://missing-v2-reward-parent/save.json"
			if not await click(world.world_travel.quest_dialogue.buttons[0]):return
		if not check(await Wait.settle(self,world),"Negative reward case settles "+failure):return
		if not await ready(func():return not world.world_travel.quest_dialogue.active,"Stopped or failed wait closes UI "+failure):return
		if not check(not backend_node.quest_auto.running and not Rules.flag(backend_node.session._profile,"now",2),"Cancel/failure cannot continue or grant request "+failure):return
		if not check(not (await rpc(other,old)).ok,"Late old choice cannot revive "+failure):return
		backend_node.save_path="user://quest-auto-v2-reward-remote.json"
	other.close();pump.queue_free()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Reward client disposed"):return
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	for suffix in ["",".bak",".tmp",".resume.json"]:
		var path:String="user://quest-auto-v2-reward-remote.json"+suffix
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("QUEST AUTO V2 REWARD REMOTE UI: PASS")
	quit(0)
