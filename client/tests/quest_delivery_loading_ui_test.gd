extends "res://tests/quest_delivery_remote_ui_test.gd"
## Cold readiness gate, real WS and production map-follow/load/report flow.
## Assets remain local for rendering; the gate must prevent reading the new map
## until its simulated cold map+music packs finish. This is not a browser/CDN test.
class ColdMapPacks extends "res://scripts/asset_packs.gd":
	var requested:Array=[]
	var waiting:Callable
	var required:Array=[]
	var available:=false
	func map_packs(map_id:int)->Array:return ["cold-map-%d"%map_id]
	func file_pack(_path:String)->String:return "cold-music"
	func is_ready(packs:Array)->bool:return packs.is_empty() or available
	func prefetch(_packs:Array)->void:pass # no cache or background warming
	func ensure(packs:Array,done:Callable=Callable(),label:String="")->void:
		requested.append({"packs":packs.duplicate(),"label":label})
		if packs.is_empty() or available:
			if done.is_valid():done.call(true)
			return
		required=packs.duplicate();waiting=done
	func finish(ok:bool)->void:
		available=ok
		var callback:=waiting;waiting=Callable()
		if callback.is_valid():callback.call(ok)
func run()->void:
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(390,844);remote_mode=true
	for succeeds in [true,false]:
		if not await loading_case(succeeds):return
	print("QUEST DELIVERY LOADING UI: PASS")
	quit(0)
func loading_case(succeeds:bool)->bool:
	backend_node=Backend.new();backend_node.set_process(false)
	backend_node.session._profile.no_random_encounters=true
	# Start at a public village exit; job12's target is Yam on map1400.
	# First landing is intermediate field100, not the task target or JOB_MAPS.
	var portal:Dictionary={}
	for link in backend_node.quest_helper.places.links(1300).values():
		if int(link.to_map)==100:portal=link;break
	if not check(not portal.is_empty(),"Original public exit to intermediate map exists"):return false
	backend_node.automation.position_changed(1300,Vector2i(int(portal.cell[0]),int(portal.cell[1])))
	root.add_child(backend_node)
	server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
	if not check(server_node.start()==OK,"Cold-map UI server port0"):return false
	if not await create_world():return false
	var original_packs=world.asset_packs
	var cold:=ColdMapPacks.new();root.add_child(cold);world.asset_packs=cold
	if not await begin_job(12):return false
	world.quest_helper_menu.close_menu()
	if not check(cold.requested.size()==1 and cold.requested[0].packs.is_empty(),"New job has no fixed startup predownload dependence"):return false
	var before:Dictionary=backend_node.session.snapshot()
	backend_node.quest_auto.tick(backend_node,0.21)
	if not check(backend_node.quest_auto.phase=="landing" and backend_node.automation.position_map==100 and int(backend_node.quest_auto.step.map_id)==1400,"Real runner enters intermediate map, not task target"):return false
	if not await ready(func():return cold.waiting.is_valid(),"Actual follow-map path requests cold destination packs"):return false
	if not check(cold.required.has("cold-map-100") and cold.required.has("cold-music"),"Actual intermediate map data and music requested dynamically"):return false
	if not check(int(world.data.map_id)==1300 and backend_node.quest_auto.phase=="landing","Unready packs prevent map read and landing confirmation"):return false
	backend_node.quest_auto.tick(backend_node,10.0)
	if not check(await Wait.settle(self,world) and backend_node.quest_auto.phase=="landing" and backend_node.session.snapshot()==before,"Downloading cannot advance source transactions"):return false
	cold.finish(succeeds)
	if succeeds:
		if not await ready(func():return int(world.data.map_id)==100 and backend_node.quest_auto.phase=="travel","Mount completion loads actual intermediate map and sends authenticated landing report"):return false
		if not check(await Wait.settle(self,world) and backend_node.quest_auto.running,"Successful dynamic load preserves strict intent"):return false
		world.quest_helper_travel.cancel()
		if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"Stop after dynamic load remains authoritative"):return false
	else:
		if not check(await Wait.settle(self,world) and int(world.data.map_id)==1300 and backend_node.quest_auto.phase=="landing","Failed download neither loads map nor sends arrival proof"):return false
		backend_node.quest_auto.tick(backend_node,21.0)
		var chip=world.find_child("QuestAutoChip",true,false)
		if not await ready(func():return chip.visible and chip.restore_button.text.contains("等待地图位置确认超时"),"Download failure ultimately retains genuine authority timeout reason"):return false
		if not check(not backend_node.quest_auto.running and backend_node.quest_auto.phase=="manual" and backend_node.session.snapshot()==before,"Unconfirmed cold map never grants transaction or auto-restarts"):return false
	world.asset_packs=original_packs;cold.queue_free()
	world.link.close();world.music.stop();world.effect.stop();world.queue_free()
	if not await ready(func():return not is_instance_valid(world),"Cold-map remote UI disposed"):return false
	server_node.stop();server_node.queue_free();backend_node.queue_free()
	return true
