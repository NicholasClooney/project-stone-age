extends RefCounted
## Test-only independent map oracle. Every step uses production report_position;
## no scope, epoch, grant, profile location, or arrival receipt is written here.
const MapFile=preload("res://scripts/map_file.gd")

static func path(backend, goal_map: int, goal: Vector2i, allowed_maps: Array) -> Array:
	var places=backend.quest_helper.places
	var maps: Dictionary={}
	var blockers: Dictionary={}
	for map_id in allowed_maps:
		var data: Dictionary=MapFile.load_map(places.file(int(map_id)))
		if data.is_empty():return []
		maps[int(map_id)]=data;blockers[int(map_id)]={}
	for npc in backend.quest_catalog.active_npcs():
		if blockers.has(int(npc.map_id)):blockers[int(npc.map_id)][Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
	var initial_map: int=backend.automation.position_map
	var initial_cell: Vector2i=backend.automation.position_cell
	if not maps.has(initial_map) or not maps.has(goal_map):return []
	# Initial position may be a genuine just-arrived portal. The authority
	# independently checks its arrival lock; this oracle never grants one.
	var start:=Vector4i(initial_map,initial_cell.x,initial_cell.y,1)
	var queue: Array[Vector4i]=[start]
	var parents: Dictionary={start:start}
	var cursor: int=0
	var found:=Vector4i(-1,-1,-1,-1)
	while cursor<queue.size():
		var node: Vector4i=queue[cursor];cursor+=1
		var point:=Vector2i(node.y,node.z)
		if node.x==goal_map and point==goal:found=node;break
		var successors: Array[Vector4i]=[]
		var portal: Dictionary=places.links(node.x).get(point,{})
		if not portal.is_empty() and node.w==0:
			if maps.has(int(portal.to_map)) and not bool(portal.get("disabled",false)) and not portal.has("gate_source"):
				successors.append(Vector4i(int(portal.to_map),int(portal.target[0]),int(portal.target[1]),1))
		else:
			var data: Dictionary=maps[node.x]
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next: Vector2i=point+delta
				if next.x<0 or next.y<0 or next.x>=int(data.width) or next.y>=int(data.height) or blockers[node.x].has(next):continue
				if int(data.blocked[next.y*int(data.width)+next.x])==0:successors.append(Vector4i(node.x,next.x,next.y,0))
		for next in successors:
			if parents.has(next):continue
			parents[next]=node;queue.append(next)
	if found.x<0:return []
	var result: Array=[]
	while found!=start:
		result.push_front({"map_id":found.x,"cell":[found.y,found.z]})
		found=parents[found]
	return result

static func walk(backend, goal_map: int, goal: Vector2i, allowed_maps: Array) -> Dictionary:
	if backend.automation.position_map==goal_map and backend.automation.position_cell==goal:return {"ok":true,"steps":0}
	var steps: Array=path(backend,goal_map,goal,allowed_maps)
	if steps.is_empty():return {"ok":false,"reason":"No original walking/portal path; script doors and guards must be completed separately."}
	for step in steps:
		var reply: Dictionary=backend.handle({"type":"report_position","map_id":step.map_id,"cell":step.cell,"client":"original-route-test"})
		if not reply.get("ok",false):return reply
	return {"ok":true,"steps":steps.size()}

## Gameplay-level setup for downstream suites. Only the initial public-village
## position is a fixture; the level-gated entrance, both channel walks, source
## dialogues, item exchange and END4 all execute production commands.
static func complete_adult(backend) -> Dictionary:
	backend.automation.position_changed(10202,Vector2i(31,13))
	var entered: Dictionary=backend.handle({"type":"report_position","map_id":10204,"cell":[2,6]})
	if not entered.get("ok",false):return entered
	for id in ["jaruga/event/event04_1","jaruga/event/event04_2","jaruga/event/event04_1"]:
		var result: Dictionary=exchange_from_route(backend,id,[10204])
		if not result.get("ok",false):return result
	return {"ok":preload("res://server/original_quests.gd").flag(backend.session.snapshot(),"ended",4)}

static func exchange_from_route(backend, npc_id: String, allowed_maps: Array) -> Dictionary:
	var npc: Dictionary=backend.original_quests.npc_by_id(npc_id)
	if npc.is_empty():return {"ok":false,"reason":"Missing original NPC"}
	var near: Dictionary=backend.quest_helper.adult_walk_destination(backend,npc) if int(npc.map_id)==10204 and backend.quest_helper.has_method("adult_walk_destination") else backend.quest_helper.destination(backend,npc,"near")
	# Tightened production helpers only return a public entrance or the
	# current nearby cell. Tests need the owner's pure geometry to walk.
	if backend.quest_helper.has_method("geometric_destination") and ResourceLoader.exists("res://server/legacy_cave_helper.gd"):
		var legacy: Script=load("res://server/legacy_cave_helper.gd")
		if legacy.owns(npc):near=legacy.walk_destination(backend.quest_helper,backend,npc)
	if near.is_empty():return {"ok":false,"reason":"Missing original dialogue position"}
	var moved: Dictionary=walk(backend,int(near.map_id),Vector2i(int(near.cell[0]),int(near.cell[1])),allowed_maps)
	if not moved.get("ok",false):return moved
	var result: Dictionary=backend.handle({"type":"quest_talk","npc_id":npc_id})
	for i in range(3):
		if not result.get("ok",false) or not result.has("dialogue"):return result
		var phase: String=str(backend.original_quests.pending.get("phase",""))
		result=backend.handle({"type":"quest_choose","token":result.dialogue.token,"choice":"ok" if phase in ["reward","end"] else "yes"})
	return result
