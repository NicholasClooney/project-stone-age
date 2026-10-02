extends "res://tests/quest_helper_ui_test.gd"
const Backend=preload("res://server/backend.gd")
const Server=preload("res://server/ws_server.gd")
const Socket=preload("res://network/ws_link.gd")
var observer
func poll_observer() -> void:
	if observer!=null:observer.poll(0.01)
func request(link,command:Dictionary) -> Dictionary:
	var received:Array=[]
	link.request(command,func(reply):received.append(reply))
	if not await ready(func():return not received.is_empty(),"Actual socket reply"):return {}
	return received[0]
func contains_stage(events:Array,id:String) -> bool:
	for event in events:
		if str(event.get("type",""))!="profile":continue
		for q in event.get("derived",{}).get("quest_helper",{}).get("quests",[]):
			if int(q.event)==44 and q.steps.any(func(s):return str(s.id)==id and bool(s.current)):return true
	return false
func profile_count(events:Array) -> int:
	return events.filter(func(event):return str(event.get("type",""))=="profile").size()
func run() -> void:
	process_frame.connect(poll_observer)
	var host=Backend.new();root.add_child(host)
	host.session.gm_raise_level(-1,30)
	host.session._profile.default_companions_claimed=true
	host.session._profile.no_random_encounters=true
	# A source-complete post-quiz fixture; walk the actual collision path and
	# original stair portal. No direct report_position for the successful warp.
	host.session.set_location(800,29,15);host.automation.position_changed(800,Vector2i(29,15),true)
	var server=Server.new(host,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Two-device helper server"):return
	var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
	world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://golden-bui-helper-remote.cfg"
	var first:Array=[];var second:Array=[]
	root.add_child(world)
	world.link.message.connect(func(event):first.append(event.duplicate(true)))
	observer=Socket.new("ws://127.0.0.1:%d"%server.port)
	observer.message.connect(func(event):second.append(event.duplicate(true)))
	observer.connect_now()
	if not await ready(func():return world.link.online and observer.online and int(world.data.get("map_id",-1))==800,"Both sockets connected to original floor"):return
	if not check(await Wait.settle(self,world),"Scene startup position settled"):return
	await request(observer,{"type":"ping"})
	first.clear();second.clear()
	var stairs:=Vector2i(-1,-1)
	for portal in world.world_catalog.links(800).values():
		if int(portal.to_map)==801:stairs=Vector2i(int(portal.cell[0]),int(portal.cell[1]));break
	if not check(stairs.x>=0,"Original800→801 stair exists"):return
	world.walk_to(stairs)
	if not await ready(func():return int(world.data.map_id)==801 and not world.area_transition_busy and not world.moving,"Production walk crosses original800→801 stair"):return
	if not check(await Wait.settle(self,world),"Natural stair report settled"):return
	await request(observer,{"type":"ping"})
	if not check(contains_stage(first,"golden44:coupon:801") and contains_stage(second,"golden44:coupon:801"),"Natural stair publishes new helper stage to both real sockets"):return
	var current:Dictionary={}
	for q in world.state.derived.quest_helper.quests:
		if int(q.event)==44:current=q
	if not check(current.steps.any(func(s):return str(s.id)=="golden44:coupon:801" and s.current),"Remote scene actually consumes changed helper projection"):return
	var target:=Vector2i(-1,-1)
	for offset in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
		var point:Vector2i=world.cell+offset
		if world.is_walkable(point) and not world.world_catalog.links(801).has(point):target=point;break
	if not check(target.x>=0 and target.y>=19,"Same original entry component neighbour available"):return
	first.clear();second.clear();world.walk_to(target)
	if not await ready(func():return world.cell==target and not world.moving,"Actual same-region step completes"):return
	if not check(await Wait.settle(self,world),"Same-region report settled"):return
	await request(observer,{"type":"ping"})
	if not check(profile_count(first)==0 and profile_count(second)==0,"Same-region movement adds no profile/helper broadcast on either socket"):return
	var stale:=await request(observer,{"type":"quest_visit","quest_id":2,"step_id":"golden44:challenge:800","npc_id":"genout/quz_800_29_19@800:29:19","mode":"near"})
	if not check(not stale.ok and host.automation.position_map==801,"Other device's old stage/npc target cannot cross back to previous floor"):return
	# Existing backend rejection, with no reordering or additional validation.
	host.session._profile.player.level=29;host.publish()
	await request(world.link,{"type":"ping"});await request(observer,{"type":"ping"})
	first.clear();second.clear()
	var rejected:=await request(observer,{"type":"report_position","map_id":10204,"cell":[20,20],"map_changed":true})
	await request(world.link,{"type":"ping"})
	if not check(not rejected.ok and host.automation.position_map==801 and profile_count(first)==0 and profile_count(second)==0,"Rejected invalid-for-level position never publishes helper/profile"):return
	host.quest_catalog.enabled_events.erase(44)
	if not check(host.quest_helper.navigation_key(host)==[],"Disabled44 has explicitly empty stage key"):return
	first.clear();second.clear()
	# Isolate this command from the scene's existing follow-map checkpoint.
	# Normal reporter client id suppresses follow; both sockets still observe events.
	var moved:=await request(observer,{"type":"report_position","map_id":800,"cell":[14,26],"client":world._client_id})
	await request(world.link,{"type":"ping"})
	if not check(moved.ok and profile_count(first)==0 and profile_count(second)==0,"Disabled44 causes no additional movement profile broadcast"):return
	process_frame.disconnect(poll_observer);observer.close();observer=null
	world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free()
	await process_frame
	print("GOLDEN BUI HELPER REMOTE: %d failures"%failures)
	quit(1 if failures else 0)
