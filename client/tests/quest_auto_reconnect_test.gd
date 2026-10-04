extends "res://tests/original_quest_auto_test.gd"
func run() -> void:
	if not detached_defeat():return
	var directory:="user://quest-reconnect-profiles"
	remove_tree(directory)
	var hub=preload("res://server/profile_hub.gd").new(directory.path_join("accounts.json"))
	hub.tick=false;hub.share_dir="";root.add_child(hub)
	if not check(hub.start(),"Isolated reconnect profiles start"):return
	var server=preload("res://server/ws_server.gd").new(hub,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Authenticated reconnect server port0"):return
	var pump:=LinkPump.new();root.add_child(pump)
	var url:="ws://127.0.0.1:%d"%server.port
	var first=preload("res://network/ws_link.gd").new(url)
	var other=preload("res://network/ws_link.gd").new(url)
	pump.links=[first,other];first.connect_now();other.connect_now()
	if not await ready(func():return first.awaiting_login and other.awaiting_login,"Real peers reach authentication"):return
	if not check((await rpc(first,{"type":"create_profile","name":"Alice","pin":"1111"})).ok,"Create Alice"):return
	if not check((await rpc(other,{"type":"create_profile","name":"Bob","pin":"2222"})).ok,"Create Bob"):return
	var b=hub.backends.alice
	prepare(b)
	if not check((await rpc(first,{"type":"quest_auto_start","quest_id":11,"client":"first"})).ok,"Start original shell task"):return
	reach_landing(b)
	if not check(b.quest_auto.phase=="landing","Task waits for genuine map confirmation"):return
	var point:Dictionary=b.quest_auto.target.duplicate(true)
	var step:Dictionary=b.quest_auto.step.duplicate(true)
	var profile:Dictionary=b.session.snapshot()
	first.close()
	if not await ready(func():return b.quest_auto.detached and hub.connections_of("alice").is_empty(),"Disconnect detaches instead of cancelling"):return
	b.quest_auto.tick(b,45.0)
	if not check(b.quest_auto.running and b.quest_auto.phase=="landing" and b.session.snapshot()==profile,"Disconnect neither times out nor grants arrival/transactions"):return
	# Authenticated Bob can only operate Bob, even with forged profile and tags.
	await rpc(other,{"type":"report_position","map_id":point.map_id,"cell":point.cell,"profile":"alice","client":"first","_quest_connection":999})
	await rpc(other,{"type":"quest_auto_stop","profile":"alice","quest_id":11})
	if not check(b.quest_auto.detached and b.quest_auto.running and b.quest_auto.step==step,"Other profile cannot acquire or stop Alice"):return
	var returning=preload("res://network/ws_link.gd").new(url)
	pump.links=[other,returning];returning.connect_now()
	if not await ready(func():return returning.awaiting_login,"New socket awaits login"):return
	var refused:Dictionary=await rpc(returning,{"type":"report_position","map_id":point.map_id,"cell":point.cell,"client":"first","profile":"alice"})
	if not check(not refused.ok and b.quest_auto.detached,"Unauthenticated socket cannot claim task"):return
	if not check((await rpc(returning,{"type":"login","name":"Alice","pin":"1111"})).ok,"Same profile reconnects"):return
	if not check(b.quest_auto.detached and b.quest_auto.phase=="landing","Login alone grants no arrival"):return
	if not check((await rpc(returning,{"type":"report_position","map_id":point.map_id,"cell":point.cell,"client":"new-client","_quest_connection":999})).ok,"New client confirms actual authority location"):return
	if not check(not b.quest_auto.detached and b.quest_auto.phase=="travel" and b.quest_auto.client=="new-client" and b.quest_auto.connection!=999 and b.quest_auto.step==step,"Transport identity rebinds existing task after valid report"):return
	if not check((await rpc(other,{"type":"login","name":"Alice","pin":"1111"})).ok,"Second device authenticates as Alice"):return
	if not check((await rpc(other,{"type":"quest_auto_stop"})).ok and not b.quest_auto.running,"Second same-profile device can stop"):return
	if not check((await rpc(returning,{"type":"quest_auto_start","quest_id":11,"client":"new-client"})).ok,"Restart before explicit logout"):return
	if not check((await rpc(returning,{"type":"logout"})).ok and not b.quest_auto.running,"Explicit owner logout still stops task"):return
	var weak_hub=weakref(hub)
	server.stop();other.close();returning.close();hub.shut_down()
	pump.queue_free();server.queue_free();hub.queue_free()
	if not await ready(func():return weak_hub.get_ref()==null,"Reconnect profile fixture disposed"):return
	remove_tree(directory)
	print("QUEST AUTO RECONNECT: PASS")
	quit(0)

func detached_defeat() -> bool:
	var b=Backend.new()
	var spawn:Array=b.quest_helper.places.info(1000).spawn
	b.automation.position_changed(1000,Vector2i(spawn[0],spawn[1]))
	for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
	# Meet only the real entrance level: leave every new stat point unspent so
	# the original weak character still loses a genuine channel encounter.
	var weak_stats:Dictionary=b.session._profile.player.base_stats.duplicate(true)
	if not check(b.session.gm_raise_level(-1,30) and b.session._profile.player.base_stats==weak_stats,"Level30 fixture retains weak unallocated combat stats"):return false
	if not check(not b.quest_arrival.has_arrival(b,10204,Vector2i(2,6)),"Fixture starts without ritual arrival authority"):return false
	b.encounter_rng.seed=7
	var route:Array=[]
	if not check(b.handle({"type":"quest_auto_start","quest_id":1,"client":"test","_quest_connection":123}).ok,"Weak adult fixture starts original task"):return false
	for index in range(5000):
		if b.quest_auto.phase=="battle":break
		# Keep the original weak-defeat fixture at the ritual encounter: public
		# approach still walks every cell, with the existing no-encounter toggle.
		b.session._profile.no_random_encounters=b.automation.position_map!=10204
		b.quest_auto.tick(b,0.21)
		var position:Array=[b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y]
		if route.is_empty() or route[-1]!=position:route.append(position)
		if b.quest_auto.phase=="landing":b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test","_quest_connection":123})
	if not check(b.quest_auto.phase=="battle","Original walk creates real battle before disconnect"):return false
	if not check(route.has([10202,31,13]) and route.has([10204,2,6]) and route[0][0]==1000 and b.quest_arrival.has_arrival(b,10204,b.automation.position_cell),"Runner crosses level30 original gate and earns continuous walking authority"):return false
	b.quest_auto.detach(b,123)
	for index in range(200):
		if not b.quest_auto.running:break
		b.automation.tick(1.0)
		b.quest_auto.tick(b,0.21)
	var safe:bool=not b.quest_auto.running and not b.automation.running and str(b.battle_state.get("outcome",""))=="defeat" and not Rules.flag(b.session._profile,"ended",4)
	b.free()
	return check(safe,"Real detached defeat still stops automation without quest reward")
