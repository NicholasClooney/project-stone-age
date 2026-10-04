extends "res://tests/quest_auto_v2_motion_remote_ui_test.gd"
## Real audited B/C moves and client presentation over two WS connections.
## Initial public placement and held render/load gates are explicit fixtures.
const Encounters=preload("res://server/encounter_catalog.gd")
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
	for scenario in ["B","C","settings","reconnect","cancel","encounter","cold"]:
		print("SEGMENT UI CASE ",scenario)
		backend_node=RecordingBackend.new();backend_node.set_process(false)
		backend_node.quest_catalog.enabled_events=[2]
		backend_node.session._profile.original_savepoint_bits=2
		backend_node.session._profile.no_random_encounters=true
		backend_node.automation.position_changed(100,Vector2i(637,494))
		root.add_child(backend_node)
		server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
		if not check(server_node.start()==OK,"Segment UI port0"):return
		if not await create_world():return
		var pump:=LinkPump.new();root.add_child(pump)
		var other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port);pump.links=[other];other.connect_now()
		if not await ready(func():return other.online,"Second authenticated segment device"):return
		var mode:="B" if scenario in ["B","cold"] else "C"
		if not check((await rpc(world.link,{"type":"set_automation_settings","settings":{"quest":{"mode":mode}}})).ok,"Real mode setting saved"):return
		if not check((await rpc(world.link,{"type":"quest_auto_start","quest_id":11,"client":world._client_id})).ok,"Start actual audited shell route"):return
		if not check(await Wait.settle(self,world) and world.state.derived.quest_auto.effective_mode==mode,"Selected effective policy published to backend-null UI"):return
		world.area_transition_busy=true
		if scenario=="encounter":
			var npc:Dictionary=backend_node.original_quests.npc_by_id("sainasu/event/event02_1")
			var points:Array=backend_node.quest_auto.navigation.next_segment(backend_node,npc,"C",3).points
			var chosen:=-1
			for seed_value in range(10000):
				var rng:=RandomNumberGenerator.new();rng.seed=seed_value
				var source=Encounters.new(backend_node.encounter_catalog.data)
				var hit:=-1
				for index in range(3):
					if source.step(100,Vector2i(points[index].cell[0],points[index].cell[1]),rng):hit=index;break
				if hit==1:chosen=seed_value;break
			if not check(chosen>=0,"Actual encounter seed hits second original cell"):return
			backend_node.encounter_rng.seed=chosen;backend_node.session._profile.no_random_encounters=false
		for index in range(1 if mode=="B" else 2 if scenario=="encounter" else 3):backend_node.quest_auto.tick(backend_node,0.21)
		if not check(await Wait.settle(self,world),"Actual prefix events settle before rendering"):return
		if scenario=="encounter":
			if not check(backend_node.quest_auto.phase=="battle" and world._remote.quest_prefix.is_empty() and world.get_meta("quest_position_receipt",{}).is_empty(),"First original hit clears UI prefix and ACK capability"):return
			world.area_transition_busy=false
			backend_node.quest_auto.stop(backend_node)
		else:
			var packet:Dictionary=backend_node.quest_auto.issued[-1].duplicate(true)
			if not check(backend_node.quest_auto.phase=="segment_landing" and packet.quest_ack_required and not has_ack(packet),"Ready gate blocks final ACK for actual B/C segment"):return
			await rpc(other,ack_of(packet))
			await rpc(world.link,{"type":"report_position","map_id":packet.map_id,"cell":packet.cell,"client":world._client_id})
			if not check(backend_node.quest_auto.phase=="segment_landing","Other transport and untagged report cannot release fast endpoint"):return
			backend_node.reports.clear()
			if scenario=="cancel":
				await rpc(other,{"type":"quest_auto_stop"})
				if not check(await Wait.settle(self,world) and world._remote.quest_prefix.is_empty(),"Remote cancellation removes pending prefix"):return
				world._remote._on_backend_message(packet);world.area_transition_busy=false
				if not check(world.get_meta("quest_position_receipt",{}).is_empty() and not has_ack(packet),"Late final prefix cannot revive cancelled display or ACK"):return
			else:
				if scenario=="settings":
					if not check((await rpc(other,{"type":"set_automation_settings","settings":{"quest":{"mode":"B"}}})).ok,"Other device saves endpoint setting"):return
					if not check(await Wait.settle(self,world),"Replacement identity reaches UI"):return
					var fresh:Dictionary=backend_node.quest_auto.issued[-1].duplicate(true)
					world._remote._on_backend_message(packet)
					if not check(fresh.quest_revision!=packet.quest_revision and world.get_meta("quest_position_receipt",{}).quest_revision==fresh.quest_revision,"Old packet cannot borrow newly signed settings identity"):return
					packet=fresh
				if scenario=="reconnect":
					world.link.close()
					if not await ready(func():return backend_node.quest_auto.detached and not world.link.online,"Actual owner disconnect clears cursor"):return
					if not check(world._remote.quest_prefix.is_empty(),"Disconnected old prefix discarded"):return
					world.link.connect_now()
					if not await ready(func():return world.link.online,"Same UI reauthenticates"):return
				world.area_transition_busy=false
				var displayed:Array=[]
				if not await ready(func():
					if displayed.is_empty() or displayed.back()!=world.cell:displayed.append(world.cell)
					return backend_node.quest_auto.phase=="travel","Ready UI completes exact segment acknowledgement"):return
				if scenario=="reconnect":
					if not check(not has_ack(packet),"Old connection capability is never retransmitted"):return
					packet=backend_node.quest_auto.issued[-1].duplicate(true)
					if not check(packet.quest_segment.mode=="A" and packet.quest_segment.kind=="walk" and packet.quest_ack_required,"Rebind correction is A/walk but still requires ACK"):return
				if not check(has_ack(packet),"UI sends complete frozen final identity"):return
				if scenario=="C":
					for point in packet.quest_segment.cells:
						if not check(Vector2i(point.cell[0],point.cell[1]) in displayed,"Every committed C cell is presented before ACK"):return
				if scenario=="cold":
					var original_packs=world.asset_packs
					var cold:=ColdMapPacks.new();root.add_child(cold);world.asset_packs=cold
					backend_node.quest_auto.tick(backend_node,0.21);backend_node.quest_auto.tick(backend_node,0.21)
					var portal_packet:Dictionary=backend_node.quest_auto.issued[-1].duplicate(true)
					if not await ready(func():return cold.waiting.is_valid(),"B endpoint still walks original portal and cold-loads its map"):return
					if not check(backend_node.quest_auto.phase=="landing" and not has_ack(portal_packet),"Cold original portal holds complete ACK"):return
					cold.finish(true)
					if not await ready(func():return backend_node.quest_auto.phase=="travel" and int(world.data.map_id)==2000,"Cold ready loads real original destination"):return
					if not check(has_ack(portal_packet),"Cold completion sends correct portal event capability"):return
					world.asset_packs=original_packs;cold.queue_free()
		if backend_node.quest_auto.running:await rpc(other,{"type":"quest_auto_stop"})
		other.close();pump.queue_free()
		world.link.close();world.music.stop();world.effect.stop();world.queue_free()
		if not await ready(func():return not is_instance_valid(world),"Segment UI disposed"):return
		server_node.stop();server_node.queue_free();backend_node.queue_free()
	if not await restart_case():return
	print("QUEST AUTO V2 SEGMENT REMOTE UI: PASS");quit(0)

func restart_case()->bool:
	var path:="user://quest-auto-v2-segment-restart.json"
	var saved=Backend.new();saved.set_process(false)
	saved.quest_catalog.enabled_events=[2];saved.save_path=path
	saved.session._profile.original_savepoint_bits=2;saved.session._profile.no_random_encounters=true
	saved.automation.position_changed(100,Vector2i(637,494))
	if not check(saved.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"C"}}}).ok,"Persist C before real restart fixture"):return false
	if not check(saved.handle({"type":"quest_auto_start","quest_id":11,"client":"before-restart"}).ok,"Start saved C intent"):return false
	saved.keep_resume_file();saved.free()
	backend_node=RecordingBackend.new();backend_node.set_process(false);backend_node.save_path=path
	backend_node.quest_catalog.enabled_events=[2]
	if not check(backend_node.load_profile(path),"Read actual saved profile into new backend"):return false
	backend_node.load_resume()
	if not check(backend_node.quest_auto.running and backend_node.quest_auto.execution_mode=="A","No-device restart uses conservative A"):return false
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Restart UI server port0"):return false
	if not await create_world():return false
	if not check(world.quest_helper_travel.auto_mode().contains("实际 A") and world.quest_helper_travel.auto_mode().contains("意图 C") and world.quest_helper_travel.auto_status().contains("重新启动任务"),"Actual reloaded snapshot explains retained C preference and current A"):return false
	if not check((await rpc(world.link,{"type":"quest_auto_stop"})).ok,"Explicitly stop restored intent"):return false
	if not check((await rpc(world.link,{"type":"quest_auto_start","quest_id":11,"client":world._client_id})).ok,"Explicit fresh start"):return false
	if not check(await Wait.settle(self,world) and world.state.derived.quest_auto.effective_mode=="C","Only fresh start applies persisted C"):return false
	await rpc(world.link,{"type":"quest_auto_stop"})
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Restart UI disposed"):return false
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	for file in [path,path+".bak",path+".tmp",path.get_basename()+".resume.json"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	return true
