extends "res://tests/original_fixed_guards_test.gd"
const Arrival=preload("res://server/quest_legitimate_arrival.gd")
const WorldClock=preload("res://server/original_world_clock.gd")

func observed(b, a, map_id: int, cell: Vector2i, kind: String="report", evidence: Dictionary={}) -> void:
	var before_map: int=b.automation.position_map
	var before_cell: Vector2i=b.automation.position_cell
	b.automation.position_changed(map_id,cell)
	a.observe_move(b,before_map,before_cell,map_id,cell,kind,evidence)

func enter(b,a) -> void:
	b.automation.position_changed(400,Vector2i(97,119))
	observed(b,a,41,Vector2i(11,8))
	check(a.has_arrival(b,41,Vector2i(11,8)),"real timed root begins one route")

func maze_path(b) -> Array:
	# Independent four-neighbour oracle on the actual map, including arrival
	# locks: stepping onto a portal must take it, arrival may walk off once.
	var data: Dictionary=preload("res://scripts/map_file.gd").load_map(b.quest_helper.places.file(41))
	var portals: Dictionary=b.quest_helper.places.links(41)
	var blocked: Dictionary={}
	for npc in b.quest_catalog.active_npcs():
		if int(npc.map_id)==41:blocked[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
	var start:=Vector3i(11,8,1)
	var queue: Array[Vector3i]=[start]
	var parents: Dictionary={start:start}
	var cursor:=0
	var goal:=Vector3i(-1,-1,-1)
	while cursor<queue.size():
		var node: Vector3i=queue[cursor];cursor+=1
		var point:=Vector2i(node.x,node.y)
		if point==Vector2i(34,42):goal=node;break
		var next_nodes: Array[Vector3i]=[]
		if portals.has(point) and node.z==0:
			var portal: Dictionary=portals[point]
			if int(portal.to_map)==41:next_nodes.append(Vector3i(int(portal.target[0]),int(portal.target[1]),1))
		else:
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next: Vector2i=point+delta
				if next.x<0 or next.y<0 or next.x>=int(data.width) or next.y>=int(data.height) or blocked.has(next):continue
				if int(data.blocked[next.y*int(data.width)+next.x])==0:next_nodes.append(Vector3i(next.x,next.y,0))
		for next in next_nodes:
			if parents.has(next):continue
			parents[next]=node;queue.append(next)
	check(goal.x>=0,"independent original maze reaches final guard")
	var path: Array=[]
	while goal.x>=0 and goal!=start:
		path.push_front(Vector2i(goal.x,goal.y));goal=parents[goal]
	return path

func run() -> void:
	var original_clock: Callable=WorldClock.clock
	WorldClock.clock=func():return WorldClock.ERA+100
	var b=fresh()
	var a=Arrival.new()
	var sage: Dictionary=b.original_quests.npc_by_id("seimu/event/event01_2@41:34:25")
	var guard: Dictionary=b.original_quests.npc_by_id("400/sb_muge1.arg@41:34:41")
	var public_npc: Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
	check(a.check_action(b,public_npc,public_npc.branches[1],"reward").is_empty(),"ordinary village delivery gets no pilgrimage requirement")
	observed(b,a,41,Vector2i(34,26),"project")
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"catch teleport cannot reward")
	observed(b,a,41,Vector2i(8,14),"project")
	var portal: Dictionary=b.quest_helper.places.links(41)[Vector2i(8,14)]
	observed(b,a,41,Vector2i(int(portal.target[0]),int(portal.target[1])))
	check(not a.has_arrival(b,41,b.automation.position_cell),"teleport onto internal portal cannot launder route")
	enter(b,a)
	var route: Array=maze_path(b)
	for point in route:
		observed(b,a,41,point)
		check(a.has_arrival(b,41,point),"continuous original maze step %s"%point)
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"reaching final guard is not winning it")
	var proof: Dictionary=a.battle_context(b,guard,guard.branches[0])
	var pending: Dictionary={"npc_id":guard.id,"warp":guard.branches[0].actions.Warp,"arrival":proof}
	check(a.check_battle(b,pending).is_empty(),"server issued guard proof verifies")
	var forged: Dictionary=pending.duplicate(true);forged.arrival.epoch+=1
	check(not a.check_battle(b,forged).is_empty(),"modified proof fails")
	var other=Arrival.new()
	check(not other.check_battle(b,pending).is_empty(),"another character cannot inherit proof")
	# Real combat and real filesystem save failure. Shared owner hooks are
	# explicitly invoked here until their separate integration commit lands.
	var talk: Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
	check(talk.ok and choose(b,talk,"yes").ok,"real ten-enemy guard starts")
	b.session._pending.quest_guard.arrival=proof
	b.save_path="user://missing-legitimate-arrival/fail.json"
	fight(b)
	check(not b.battle_state.get("settled",false) and a.check_battle(b,pending).is_empty(),"savefail retains same route proof for retry")
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"failed save has no final arrival")
	b.save_path=""
	b._after_turn(b.battle.snapshot())
	check(bool(b.battle_state.get("settled",false)),"same combat result retries")
	a.battle_committed(b,pending)
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"saved win before Warp is not arrival")
	var old: Vector2i=b.automation.position_cell
	b.close_battle()
	a.observe_move(b,41,old,41,b.automation.position_cell,"script")
	check(a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"only successful original victory Warp authorizes sage")
	observed(b,a,41,Vector2i(34,38))
	check(a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"normal postbattle walking retains proof")
	observed(b,a,41,Vector2i(34,26),"project")
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"same-map project jump invalidates old final proof")
	a.battle_committed(b,pending)
	observed(b,a,41,Vector2i(34,39),"script")
	check(not a.has_arrival(b,41,b.automation.position_cell),"old committed battle cannot reissue route")
	enter(b,a)
	a.reset()
	check(not a.has_arrival(b,41,Vector2i(11,8)),"restart and loaded location do not restore route")
	check(a.blocked_guard_items({"npc_id":"100/sb_nusu1.arg"}).is_empty(),"client-named guard alone cannot suppress ordinary loot")
	check(a.blocked_guard_items({}).is_empty(),"wild combat has no guard loot exclusion")
	var thief: Dictionary=b.original_quests.npc_by_id("100/sb_nusu1.arg@10701:23:51")
	b.automation.position_changed(10701,Vector2i(23,52))
	var thief_proof: Dictionary=a.battle_context(b,thief,thief.branches[0])
	var thief_pending: Dictionary={"npc_id":thief.id,"warp":"","arrival":thief_proof}
	observed(b,a,1000,Vector2i(20,20),"project")
	check(a.blocked_guard_items(thief_pending)==[2428],"only issued actual guard identity lists its precise task drop after epoch invalidation")
	thief_pending.npc_id="100/sb_nusu2.arg@10703:6:63"
	check(a.blocked_guard_items(thief_pending).is_empty(),"altering the source identity cannot suppress another guard drop")
	var forged_npc: Dictionary=thief.duplicate(true);forged_npc.map_id=1000
	check(a.battle_context(b,forged_npc,thief.branches[0]).is_empty(),"same name with forged NPC definition cannot issue guard proof")
	WorldClock.clock=original_clock
	b.free()
	print("QUEST LEGITIMATE ARRIVAL: %d failures"%failures)
	quit(1 if failures else 0)
