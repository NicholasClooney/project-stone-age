extends "res://tests/quest_delivery_loading_ui_test.gd"
## Actual A original portal + cold-map gate + two WS devices. B/C not enabled.
class RecordingBackend extends "res://server/backend.gd":
	var reports:Array=[]
	func handle(command:Dictionary)->Dictionary:
		if str(command.get("type",""))=="report_position":reports.append(command.duplicate(true))
		return super.handle(command)
const FIELDS=["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]
func ack_of(packet:Dictionary)->Dictionary:
	var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":world._client_id}
	for field in FIELDS:command[field]=packet[field]
	return command
func has_ack(packet:Dictionary)->bool:
	for command in backend_node.reports:
		var same:=true
		for field in FIELDS:
			if command.get(field)!=packet[field]:same=false
		if same and command.get("map_id")==packet.map_id and command.get("cell")==packet.cell:return true
	return false
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
	for scenario in ["ready","cancel","reconnect","reconnect_travel"]:
		print("MOTION CASE ",scenario)
		backend_node=RecordingBackend.new();backend_node.set_process(false)
		backend_node.session._profile.no_random_encounters=true
		var portal:Dictionary={}
		for candidate in backend_node.quest_helper.places.links(1300).values():
			if int(candidate.to_map)==100:portal=candidate;break
		if not check(not portal.is_empty(),"Actual village portal available"):return
		backend_node.automation.position_changed(1300,Vector2i(portal.cell[0],portal.cell[1]))
		root.add_child(backend_node)
		server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
		if not check(server_node.start()==OK,"Motion UI server port0"):return
		if not await create_world():return
		var original_packs=world.asset_packs
		var cold:=ColdMapPacks.new();root.add_child(cold);world.asset_packs=cold
		if not await begin_job(12):return
		world.quest_helper_menu.close_menu()
		backend_node.quest_auto.tick(backend_node,0.21)
		var packet:Dictionary=backend_node.quest_auto.issued[-1].duplicate(true)
		if not await ready(func():return cold.waiting.is_valid(),"New receipt starts cold intermediate map load"):return
		if not check(backend_node.quest_auto.phase=="landing" and not has_ack(packet) and int(world.data.map_id)==1300,"No acknowledgement before actual map readiness"):return
		var pump:=LinkPump.new();root.add_child(pump)
		var other=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server_node.port);pump.links=[other];other.connect_now()
		if not await ready(func():return other.online,"Second motion device connects"):return
		await rpc(other,ack_of(packet))
		if not check(backend_node.quest_auto.phase=="landing","Second device cannot acknowledge owner's segment"):return
		backend_node.reports.clear()
		if scenario=="ready":
			cold.finish(true)
			if not await ready(func():return int(world.data.map_id)==100,"Downloaded map has built"):return

			if not await ready(func():return backend_node.quest_auto.phase=="travel" and int(world.data.map_id)==100,"Map readiness releases A landing"):return
			if not check(has_ack(packet),"Actual UI sends all five original event fields with shown cell"):return
			var current_receipt:Dictionary=world.get_meta("quest_position_receipt",{}).duplicate(true)
			world._remote._on_backend_message(packet)
			if not check(world.get_meta("quest_position_receipt",{})==current_receipt,"Duplicate event cannot replace acknowledged receipt"):return
		elif scenario=="cancel":
			var late:Callable=cold.waiting
			if not check((await rpc(other,{"type":"quest_auto_stop"})).ok,"Other device cancels during cold load"):return
			if not check(await Wait.settle(self,world),"Cancel snapshot settles"):return
			if not check(world.get_meta("quest_position_receipt",{}).is_empty(),"Cancellation clears event capability"):return
			cold.available=true;late.call(true)
			if not check(not has_ack(packet) and not backend_node.quest_auto.running,"Late cancelled download never reports old segment"):return
			world._remote._on_backend_message(packet)
			if not check(world.get_meta("quest_position_receipt",{}).is_empty(),"Late old-run position packet cannot restore cancelled receipt"):return
		else:
			if scenario=="reconnect_travel":
				cold.finish(true)
				if not await ready(func():return backend_node.quest_auto.phase=="travel","Travel reconnect begins after acknowledged landing"):return
			world.link.close()
			if not await ready(func():return backend_node.quest_auto.detached and not world.link.online,"Both ends observe owner transport disconnection"):return
			if not check(world.get_meta("quest_position_receipt",{}).is_empty(),"Disconnect clears old sequence and segment"):return
			cold.finish(true)
			backend_node.reports.clear()
			world.link.connect_now()
			if not await ready(func():return world.link.online and not backend_node.quest_auto.detached and int(world.data.map_id)==100,"Reconnect follows authority and rebinds"):return
			if not check(await Wait.settle(self,world),"Rebound receipt settles"):return
			var handshake:=false
			for command in backend_node.reports:
				if command.get("client")==world._client_id and command.get("map_id")==packet.map_id and command.get("cell")==packet.cell and not command.has("quest_position_seq") and not command.has("quest_segment_id"):handshake=true
			if not check(handshake and not has_ack(packet),"Rebinding uses authority cell without any stale receipt tags"):return
			var fresh:Dictionary=world.get_meta("quest_position_receipt",{})
			if not check(not fresh.is_empty() and fresh.quest_position_seq>packet.quest_position_seq,"Rebind receives a new server-issued receipt"):return
			world.report_position()
			if not check(await Wait.settle(self,world) and has_ack(fresh),"Only new event identity may be acknowledged after reconnect"):return
		if backend_node.quest_auto.running:
			await rpc(other,{"type":"quest_auto_stop"})
		other.close();pump.queue_free();world.asset_packs=original_packs;cold.queue_free()
		world.link.close();world.music.stop();world.effect.stop();world.queue_free()
		if not await ready(func():return not is_instance_valid(world),"Motion client disposed"):return
		server_node.stop();server_node.queue_free();backend_node.queue_free()
	print("QUEST AUTO V2 MOTION REMOTE UI: PASS")
	quit(0)
