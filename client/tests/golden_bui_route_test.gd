extends SceneTree
## Real source catalog, collision paths, Backend transactions and random battles.
const Backend = preload("res://server/backend.gd")
const Rules = preload("res://server/original_quests.gd")
const Session = preload("res://server/game_session.gd")
const MapFile = preload("res://scripts/map_file.gd")
const Server = preload("res://server/ws_server.gd")
const Link = preload("res://network/ws_link.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var private_catalog: Dictionary
var links: Array = []
var drop_rollback_checked := {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, note: String) -> bool:
	if not ok:
		failures += 1
		push_error(note)
	return ok
func fresh(level: int):
	var b = Backend.new()
	b.set_process(false)
	if not 44 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(44)
	b.session.gm_raise_level(-1,level)
	b.session._profile.player.gold = 100000
	b.session._profile.pets = []
	b.session._profile.active_pet = -1
	b.session._profile.ride_pet = -1
	for key in b.session._profile.inventory: b.session._profile.inventory[key] = 0
	for stat in ["vitality","strength","toughness","dexterity"]:b.session.gm_set_base_stat(-1,stat,10000)
	b.session._profile.player.hp = b.session._profile.player.max_hp
	return b
func choose(b, reply: Dictionary, choice: String, text := "") -> Dictionary:
	return b.handle({"type":"quest_choose","token":reply.get("dialogue",{}).get("token",""),"choice":choice,"text":text})
func approach(b, id: String) -> bool:
	var npc: Dictionary = b.original_quests.npc_by_id(id)
	if not check(not npc.is_empty(),"Real NPC enabled: "+id):return false
	for offset in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
		if walk(b,Vector2i(int(npc.cell[0]),int(npc.cell[1]))+offset,false):return true
	# Original counter clerks stand behind an impassable desk. Public dialogue
	# accepts the source two-cell Chebyshev talk range, like production approach.
	for x in range(-2,3):
		for y in range(-2,3):
			if walk(b,Vector2i(int(npc.cell[0])+x,int(npc.cell[1])+y),false):return true
	return check(false,"Real source NPC has reachable neighbour "+id)
func walk(b, target: Vector2i, report_missing := true) -> bool:
	var map_id: int = b.automation.position_map
	var data := MapFile.load_map(b.session.world_catalog.file(map_id))
	if not check(not data.is_empty(),"Real original map loaded %d"%map_id):return false
	var start: Vector2i = b.automation.position_cell
	var queue: Array[Vector2i] = [start]
	var prior := {start:start}
	var doors: Dictionary = b.session.world_catalog.links(map_id)
	while not queue.is_empty() and not prior.has(target):
		var cell: Vector2i = queue.pop_front()
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+offset
			if next.x<0 or next.y<0 or next.x>=int(data.width) or next.y>=int(data.height) or prior.has(next):continue
			if int(data.blocked[next.y*int(data.width)+next.x])!=0:continue
			if doors.has(next) and next!=target:continue
			prior[next]=cell
			queue.append(next)
	if not prior.has(target):
		if report_missing:check(false,"Natural collision path %d %s→%s"%[map_id,start,target])
		return false
	var path: Array[Vector2i] = []
	var cursor := target
	while cursor!=start:
		path.push_front(cursor)
		cursor=prior[cursor]
	for cell in path:
		if not check(b.handle({"type":"report_position","map_id":map_id,"cell":[cell.x,cell.y]}).ok,"Real session step report"):return false
	return true
func portal(b, to_map: int) -> bool:
	var doors: Dictionary = b.session.world_catalog.links(b.automation.position_map)
	for point in doors:
		var door: Dictionary = doors[point]
		if int(door.to_map)!=to_map:continue
		if not walk(b,point):return false
		if not check(b.handle({"type":"check_passage","from_map":b.automation.position_map,"to_map":to_map}).ok,"Original walking portal allowed"):return false
		return check(b.handle({"type":"report_position","map_id":to_map,"cell":door.target,"map_changed":true}).ok,"Original portal exact target")
	return check(false,"Original portal exists to %d"%to_map)
func talk(b, id: String) -> Dictionary:
	if not approach(b,id):return {}
	return b.handle({"type":"quest_talk","npc_id":id})
func trade(b, id: String) -> Dictionary:
	var reply := choose(b,talk(b,id),"yes")
	if reply.has("dialogue"):reply=choose(b,reply,"ok")
	return reply
func fight(b) -> void:
	for attempt in range(100):
		var state: Dictionary = b.battle.snapshot()
		if not state.active:return
		var target := 0
		for index in range(state.enemies.size()):
			if state.enemies[index].hp>0:target=index;break
		b.handle({"type":"battle_command","action":"attack","target":target})
	check(false,"Original disciple battle terminates")
func earn(b, item: int) -> bool:
	if not check(b.session.world_catalog.field(b.automation.position_map),"Natural route classified as encounter field"):return false
	for attempt in range(120):
		if item in b.session.snapshot().original_items:return true
		var started := {}
		var origin: Vector2i=b.automation.position_cell
		var data:=MapFile.load_map(b.session.world_catalog.file(b.automation.position_map))
		var neighbour:=origin
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.UP]:
			var next: Vector2i=origin+offset
			if next.x>=0 and next.y>=0 and next.x<int(data.width) and next.y<int(data.height) and int(data.blocked[next.y*int(data.width)+next.x])==0 and not b.session.world_catalog.links(b.automation.position_map).has(next):neighbour=next;break
		if not check(neighbour!=origin,"Natural source floor has a walking encounter path"):return false
		for step in range(2000):
			var point: Vector2i=neighbour if step%2==0 else origin
			if not walk(b,point):return false
			started=b.handle({"type":"field_step","map_id":b.automation.position_map,"cell":[point.x,point.y],"encounter":true})
			if b.battle_open:break
		if not check(started.ok and b.battle_open,"Real source random dojo encounter"):return false
		for enemy in b.session._pending.enemies:
			if not check(int(enemy.source_enemy_id) in range(1287,1305),"Original random disciple ID"):return false
		var route_id:=int(b.encounter_catalog.area_at(b.automation.position_map,b.automation.position_cell).get("group_id",b.automation.position_map))
		var rollback:bool=not drop_rollback_checked.has(route_id) and b.session._pending.enemies.any(func(enemy):return not enemy.get("generated_drops",[]).is_empty())
		var before:Dictionary=b.session.snapshot()
		if rollback:b.save_path="user://golden-bui-route-blocked/child.json"
		fight(b)
		if rollback:
			check(b.session.snapshot()==before and not bool(b.battle_state.get("settled",false)),"Real generated coupon save failure restores exact profile")
			check(not b.handle({"type":"battle_close"}).ok and b.session.snapshot()==before,"Failed random battle settlement cannot close or leak coupons")
			b.save_path=""
			drop_rollback_checked[route_id]=true
		if not check(b.handle({"type":"battle_close"}).ok,"Actual battle settles and closes"):return false
		var settled:Dictionary=b.session.snapshot()
		check(not b.handle({"type":"battle_close"}).ok and b.session.snapshot()==settled,"Repeated close never awards another random coupon")
	return check(false,"Random disciple actually earns entry coupon")
func correct_answer(npc: Dictionary, reply: Dictionary) -> Dictionary:
	var rule: Dictionary = private_catalog.services[npc.service_id]
	var dialogue: Dictionary = reply.get("dialogue",{})
	for question in rule.questions:
		if not str(dialogue.get("text","")).ends_with(str(question.text)):continue
		if int(question.answer_type)==4:return {"choice":"submit","text":str(question.options[0])}
		for entry in dialogue.choices:
			if str(entry.text)==str(question.options[int(question.answer)]):return {"choice":str(entry.id),"text":""}
	return {}
func quiz(b, npc: Dictionary) -> bool:
	if not earn(b,2752):return false
	var reply := choose(b,talk(b,str(npc.id)),"yes")
	for index in range(11):
		if not check(reply.get("ok",false),"Real quiz reply accepted"):return false
		if reply.get("closed",false):return true
		var answer := correct_answer(npc,reply)
		if not check(not answer.is_empty(),"Original source question resolved in server-side fixture"):return false
		reply=choose(b,reply,answer.choice,answer.text)
	return check(false,"Original quiz series closes")
func route(base: int, level: int) -> void:
	var b = fresh(level)
	var village := 4000 if base==840 else 2000
	var counter := 4020 if base==840 else 2020
	var lobby := 851 if base==840 else 811
	b.automation.position_changed(village,Vector2i(81,107) if base==840 else Vector2i(68,51))
	if not portal(b,counter):b.free();return
	var vendor := "quiz/uketuke%s@%d:18:13"%["2" if base==840 else "",counter]
	var gold: int = b.session.snapshot().player.gold
	if not check(trade(b,vendor).ok,"Buy real level-banded ticket"):b.free();return
	if not check(b.session.snapshot().player.gold==gold-level*(20 if base==800 else 40),"Original LV ticket cost"):b.free();return
	if not portal(b,lobby):b.free();return
	var gate := "genout/wpm_%d_%d_20@%d:%d:20"%[lobby,29 if base==840 else (30 if base==800 else 28),lobby,29 if base==840 else (30 if base==800 else 28)]
	if not check(trade(b,gate).ok and b.automation.position_map==base,"Actual source receptionist consumes ticket and enters route"):b.free();return
	var finished := {}
	var attempts := 0
	while b.automation.position_map not in [810,850] and attempts<100:
		attempts+=1
		var floor_id: int = b.automation.position_map
		var candidates: Array = b.quest_catalog.active_npcs().filter(func(n):return int(n.map_id)==floor_id and str(n.get("kind","")) in ["golden_bui_quiz","golden_bui_janken"])
		if not check(candidates.size()==1,"Exactly one challenge on source floor"):break
		var npc: Dictionary = candidates[0]
		if str(npc.kind)=="golden_bui_quiz":
			if not quiz(b,npc):break
		else:
			if not earn(b,2751):break
			var reply := choose(b,talk(b,str(npc.id)),"yes")
			for hand in range(80):
				reply=choose(b,reply,"rock")
				if not reply.get("ok",false) or reply.get("closed",false):break
			if not check(reply.get("ok",false),"Actual janken result"):break
			if b.automation.position_map!=floor_id:continue
		finished[floor_id]=true
		var next := (850 if base==840 else 810) if floor_id==base+9 else floor_id+1
		if not portal(b,next):break
	check(finished.size()==10 and b.automation.position_map in [810,850],"Natural ten-floor route completed %d"%base)
	if b.automation.position_map in [810,850]:
		var room: int = b.automation.position_map
		var initial:=talk(b,"quiz/equiz_01@%d:29:16"%room)
		var before:Dictionary=b.session.snapshot()
		b.save_path="user://golden-bui-route-blocked/child.json"
		check(not choose(b,initial,"yes").ok and b.session.snapshot()==before,"Final2753 save failure cannot set NOW44 or issue reward coupon")
		b.save_path=""
		check(trade(b,"quiz/equiz_01@%d:29:16"%room).ok and 2753 in b.session.snapshot().original_items,"Actual REQUEST44 issues reward coupon")
		var reward:=choose(b,talk(b,"quiz/equiz_02@%d:28:16"%room),"yes")
		before=b.session.snapshot();b.save_path="user://golden-bui-route-blocked/child.json"
		check(not choose(b,reward,"ok").ok and b.session.snapshot()==before,"Pet exchange save failure keeps2753 and leaves END44 unset")
		b.save_path=""
		reward=choose(b,talk(b,"quiz/equiz_02@%d:28:16"%room),"yes")
		check(choose(b,reward,"ok").ok and Rules.flag(b.session.snapshot(),"ended",44),"Actual END44 exchange")
		before=b.session.snapshot()
		check(not choose(b,reward,"ok").ok and b.session.snapshot()==before,"Old reward token cannot duplicate original pet")
		check(b.session.snapshot().pets.size()==1 and b.session.snapshot().pets[0].source_enemy_id==14 and b.session.snapshot().pets[0].template_id==12,"Exact golden Bui source reward")
	b.free()
func run() -> void:
	var blocked:=FileAccess.open("user://golden-bui-route-blocked",FileAccess.WRITE)
	blocked.store_string("file blocks requested save directory");blocked.close()
	private_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/server/golden-bui.json"))
	for data in [[800,30],[820,50],[840,70]]:route(data[0],data[1])
	check(drop_rollback_checked.size()>=3,"All three route random coupon settlements exercise real save failure and retry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://golden-bui-route-blocked"))
	print("golden_bui_route_test: %d failures"%failures)
	quit(1 if failures else 0)
