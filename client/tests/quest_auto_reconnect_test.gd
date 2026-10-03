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
	if not check((await rpc(first,{"type":"quest_auto_start","quest_id":11,"client":"first"})).ok,"Start original shell task"):return
	b.quest_auto.tick(b,0.21)
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
	if not check(not b.quest_auto.detached and b.quest_auto.phase=="talk" and b.quest_auto.client=="new-client" and b.quest_auto.connection!=999 and b.quest_auto.step==step,"Transport identity rebinds existing task after valid report"):return
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
	for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
	b.encounter_rng.seed=7
	if not check(b.handle({"type":"quest_auto_start","quest_id":1,"client":"test","_quest_connection":123}).ok,"Weak adult fixture starts original task"):return false
	for index in range(1500):
		if b.quest_auto.phase=="battle":break
		b.quest_auto.tick(b,0.21)
		if b.quest_auto.phase=="landing":b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"client":"test","_quest_connection":123})
	if not check(b.quest_auto.phase=="battle","Original walk creates real battle before disconnect"):return false
	b.quest_auto.detach(b,123)
	for index in range(200):
		if not b.quest_auto.running:break
		b.automation.tick(1.0)
		b.quest_auto.tick(b,0.21)
	var safe:bool=not b.quest_auto.running and not b.automation.running and str(b.battle_state.get("outcome",""))=="defeat" and not Rules.flag(b.session._profile,"ended",4)
	b.free()
	return check(safe,"Real detached defeat still stops automation without quest reward")
