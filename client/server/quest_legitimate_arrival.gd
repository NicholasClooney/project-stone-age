extends RefCounted
## Per-character authority memory. Never serialize this object or its receipts.
const Policy=preload("res://server/quest_arrival_policy.gd")
const MapFile=preload("res://scripts/map_file.gd")
const WorldClock=preload("res://server/original_world_clock.gd")
const DENIED="项目补充：请从原入口沿原路线通过门、迷宫及守卫；项目瞬移不授予任务到达资格。"
var _epoch: int=0
var _serial: int=0
var _scope: String=""
var _map: int=-1
var _cell: Vector2i=Vector2i(-1,-1)
var _marks: Dictionary={}
var _stages: Dictionary={}
var _action: Dictionary={}
var _approach: Dictionary={}
var _warp: Dictionary={}
var _battles: Dictionary={}
var _wild: Dictionary={}
var _maps: Dictionary={}
var _can_leave_portal: bool=false
var _rooms: Dictionary={}
var _block_signature: Array=[]
var _block_cache: Dictionary={}

func reset() -> void:
	_invalidate()
	_battles.clear()
	_wild.clear()

func _invalidate() -> void:
	_epoch+=1
	_scope=""
	_map=-1
	_cell=Vector2i(-1,-1)
	_marks.clear()
	_stages.clear()
	_action.clear()
	_approach.clear()
	_warp.clear()
	_can_leave_portal=false

func observe_move(backend, from_map: int, from_cell: Vector2i, to_map: int, to_cell: Vector2i, kind: String="report", evidence: Dictionary={}) -> void:
	if from_map==to_map and from_cell==to_cell:return
	var target_scope: String=Policy.scope(to_map)
	if kind=="script":
		var receipt: Dictionary=_warp.duplicate(true)
		_warp.clear()
		if not receipt.is_empty() and int(receipt.epoch)==_epoch and int(receipt.from_map)==from_map and _point(receipt.from_cell)==from_cell and int(receipt.to_map)==to_map and _point(receipt.to_cell)==to_cell and (not target_scope.is_empty() or not str(receipt.get("approach","")).is_empty()):
			if not str(receipt.get("approach","")).is_empty():
				_begin_approach(str(receipt.approach),to_map,to_cell)
				return
			_approach.clear()
			if _scope!=target_scope:_stages.clear()
			_scope=target_scope
			_map=to_map
			_cell=to_cell
			_can_leave_portal=true
			var mark: String=str(receipt.get("mark",""))
			if not mark.is_empty():
				_serial+=1
				_marks[mark]=_serial
			var stage: String=str(receipt.get("stage",""))
			if not stage.is_empty() and Policy.stage_scope(stage)==target_scope:
				_serial+=1
				_stages[stage]=_serial
			_expire_marks(backend,to_map,to_cell)
			return
		_invalidate()
		return
	if target_scope.is_empty() and kind in ["report","walk"]:
		if _continue_approach(backend,from_map,from_cell,to_map,to_cell):return
		var returning: String=Policy.approach_return(from_map,from_cell,to_map,to_cell)
		if not returning.is_empty() and _scope==Policy.scope(from_map) and not _scope.is_empty() and _map==from_map and _cell==from_cell and _portal(backend,from_map,from_cell,to_map,to_cell,true):
			_begin_approach(returning,to_map,to_cell,true)
			return
	if target_scope.is_empty() or kind not in ["report","walk","party"]:
		_invalidate()
		return
	var valid_before: bool=_scope==Policy.scope(from_map) and not _scope.is_empty() and _map==from_map and _cell==from_cell
	if kind=="party":
		# Only ProfileHub supplies this evidence after a validated leader step.
		# A follower keeps its own route; the leader's marks are never copied.
		var leader_map: int=int(evidence.get("leader_from_map",-1))
		var leader_cell: Vector2i=_point(evidence.get("leader_from_cell",[]))
		var leader_target: Vector2i=_point(evidence.get("leader_to_cell",[]))
		if int(evidence.get("leader_to_map",-1))!=to_map or leader_map!=from_map:
			_invalidate();return
		# Ordinary party.follow moves each follower toward its predecessor's
		# previous cell, not the leader's new cell. It can only retain that
		# follower's existing route after checking both actual one-cell steps.
		var walking: bool=leader_map==to_map and _walk_step(backend,leader_map,leader_cell,leader_target,true)
		if walking and valid_before and _scope==target_scope and from_map==to_map and (_can_leave_portal or not backend.quest_helper.places.links(from_map).has(from_cell)) and _walk_step(backend,from_map,from_cell,to_cell,_can_leave_portal) and (_same_room(backend,from_map,from_cell,leader_cell) or (_can_leave_portal and _same_room(backend,from_map,to_cell,leader_cell))):
			_map=to_map;_cell=to_cell;_can_leave_portal=false;_expire_marks(backend,to_map,to_cell);return
		# A warp has one shared target, but still requires the exact source
		# portal and the member's own previous room/root eligibility.
		if leader_target!=to_cell or not _portal_approach(backend,from_map,from_cell,leader_cell):_invalidate();return
		if _portal(backend,leader_map,leader_cell,to_map,to_cell) and ((valid_before and _scope==target_scope) or (Policy.scope(from_map).is_empty() and Policy.portal_root(from_map,to_map))):
			_scope=target_scope;_map=to_map;_cell=to_cell;_can_leave_portal=true;_expire_marks(backend,to_map,to_cell);return
		_invalidate();return
	if valid_before and _scope==target_scope and from_map==to_map and (_can_leave_portal or not backend.quest_helper.places.links(from_map).has(from_cell)) and _walk_step(backend,from_map,from_cell,to_cell,_can_leave_portal):
		_map=to_map;_cell=to_cell;_can_leave_portal=false;_expire_marks(backend,to_map,to_cell);return
	if _portal(backend,from_map,from_cell,to_map,to_cell) and ((valid_before and _scope==target_scope) or (Policy.scope(from_map).is_empty() and Policy.portal_root(from_map,to_map))):
		_scope=target_scope;_map=to_map;_cell=to_cell;_can_leave_portal=true;_expire_marks(backend,to_map,to_cell);return
	_invalidate()

func has_arrival(backend, map_id: int, cell: Vector2i) -> bool:
	if Policy.scope(map_id).is_empty():return true
	if not _at_authority(backend) or _map!=map_id:return false
	return cell==_cell or _same_room(backend,map_id,_cell,cell)

## Server-only encounter receipt. Unqualified starts remain unqualified even if
## a later route is completed. Retry checks never consume or refresh a receipt.
func wild_context(backend) -> Dictionary:
	_serial+=1
	_wild={"instance":get_instance_id(),"serial":_serial,"epoch":_epoch,"scope":_scope if _at_authority(backend) else "","map_id":int(backend.automation.position_map),"cell":[backend.automation.position_cell.x,backend.automation.position_cell.y]}
	return _wild.duplicate(true)

func check_wild(backend, context: Dictionary, wanted_scope: String) -> String:
	if wanted_scope.is_empty() or context.is_empty() or context!=_wild:return DENIED
	if int(context.get("instance",-1))!=get_instance_id() or int(context.get("epoch",-1))!=_epoch:return DENIED
	if str(context.get("scope",""))!=wanted_scope or not _at_authority(backend) or _scope!=wanted_scope:return DENIED
	if int(context.map_id)!=int(backend.automation.position_map) or _point(context.cell)!=backend.automation.position_cell:return DENIED
	return ""

func check_action(backend, npc: Dictionary, branch: Dictionary, phase: String) -> String:
	if phase in ["cancel","CLEAN","end"]:return ""
	if npc.is_empty():return DENIED
	var approach: String=Policy.action_approach(npc)
	if not approach.is_empty() and not _has_approach(backend,approach):return DENIED
	var wanted: String=Policy.scope(int(npc.get("map_id",-1)))
	if wanted.is_empty():return ""
	if not _at_authority(backend) or _scope!=wanted or int(npc.map_id)!=_map:return DENIED
	for stage in Policy.action_stages(npc,branch):
		if not has_stage(backend,str(stage)):return DENIED
	for mark in Policy.action_marks(npc,branch):
		if not _marks.has(mark):return DENIED
	return ""

## Stages describe source-verified progression within a continuous scope;
## they are not final-room marks and cannot be restored from profile fields.
func has_stage(backend, stage: String) -> bool:
	return not stage.is_empty() and _at_authority(backend) and Policy.stage_scope(stage)==_scope and _stages.has(stage)

## Arrival-only proof: the service owner separately binds profile/UID/seed and
## validates source requirements. Neither the proof nor its backing record is saved.
func action_context(backend, npc: Dictionary, branch: Dictionary, phase: String) -> Dictionary:
	if Policy.scope(int(npc.get("map_id",-1))).is_empty() or int(npc.get("map_id",-1))!=_map:return {}
	if phase in ["cancel","CLEAN","end"] or not _at_authority(backend) or not check_action(backend,npc,branch,phase).is_empty():return {}
	var actual: Dictionary=backend.original_quests.npc_by_id(str(npc.get("id","")))
	if actual.is_empty() or actual!=npc:return {}
	if not branch in actual.get("branches",[]) and not (branch.is_empty() and phase=="SERVICE" and Policy.context_service(actual)):return {}
	_serial+=1
	var proof: Dictionary={"instance":get_instance_id(),"serial":_serial,"epoch":_epoch,"scope":_scope,"map_id":_map,"cell":[_cell.x,_cell.y],"npc_id":str(actual.id),"phase":phase,"marks":_marks.duplicate(true),"stages":_stages.duplicate(true)}
	_action={"proof":proof.duplicate(true),"npc":actual.duplicate(true),"branch":branch.duplicate(true)}
	return proof

func check_action_context(backend, context: Dictionary) -> String:
	if context.is_empty() or _action.is_empty() or context!=_action.proof:return DENIED
	if int(context.get("instance",-1))!=get_instance_id() or int(context.get("epoch",-1))!=_epoch or not _at_authority(backend):return DENIED
	if str(context.scope)!=_scope or int(context.map_id)!=_map or _point(context.cell)!=_cell or context.marks!=_marks or context.stages!=_stages:return DENIED
	var actual: Dictionary=backend.original_quests.npc_by_id(str(context.npc_id))
	if actual.is_empty() or actual!=_action.npc:return DENIED
	return check_action(backend,actual,_action.branch,str(context.phase))

## Called ONLY after the owning service's atomic save succeeds. Profile position
## may already be the saved return village: consume by private identity, not by
## the changed profile. Failure paths must leave this receipt untouched.
func consume_action_context(context: Dictionary) -> void:
	if context.is_empty() or _action.is_empty() or context!=_action.proof:return
	reset()

func action_committed(backend, npc: Dictionary, branch: Dictionary, phase: String) -> void:
	if phase in ["cancel","CLEAN","end"] or not check_action(backend,npc,branch,phase).is_empty():return
	var actual: Dictionary=backend.original_quests.npc_by_id(str(npc.get("id","")))
	if actual.is_empty() or actual!=npc:return
	var service: bool=phase=="SERVICE" and str(actual.get("kind","")) in ["golden_bui_gate","golden_bui_quiz","golden_bui_janken","original_jug_shop"]
	if not service and not branch in actual.get("branches",[]):return
	_queue_warp(backend,npc,str(branch.get("actions",{}).get("Warp","")),Policy.action_mark(Policy.source(npc)),Policy.action_stage(Policy.source(npc)))

func battle_context(backend, npc: Dictionary, branch: Dictionary) -> Dictionary:
	if not check_action(backend,npc,branch,"BATTLE").is_empty():return {}
	var actual: Dictionary=backend.original_quests.npc_by_id(str(npc.get("id","")))
	if actual.is_empty() or actual!=npc or not branch in actual.get("branches",[]) or str(branch.get("type",""))!="BATTLE":return {}
	_battles.clear()
	_serial+=1
	var proof: Dictionary={"instance":get_instance_id(),"serial":_serial,"epoch":_epoch,"scope":Policy.scope(int(npc.map_id)),"map_id":int(backend.automation.position_map),"cell":[backend.automation.position_cell.x,backend.automation.position_cell.y],"npc_id":str(npc.id),"warp":str(branch.get("actions",{}).get("Warp",""))}
	_battles[_serial]={"proof":proof.duplicate(true),"npc":npc.duplicate(true)}
	return proof

func check_battle(backend, pending_guard: Dictionary) -> String:
	var proof: Dictionary=pending_guard.get("arrival",{})
	var record: Dictionary=_battles.get(int(proof.get("serial",-1)),{})
	if record.is_empty() or proof!=record.proof or int(proof.get("instance",-1))!=get_instance_id() or int(proof.get("epoch",-1))!=_epoch:return DENIED
	if str(proof.npc_id)!=str(pending_guard.get("npc_id","")) or str(proof.warp)!=str(pending_guard.get("warp","")):return DENIED
	if int(backend.automation.position_map)!=int(proof.map_id) or backend.automation.position_cell!=_point(proof.cell):return DENIED
	if not str(proof.scope).is_empty() and not _at_authority(backend):return DENIED
	return ""

func battle_committed(backend, pending_guard: Dictionary) -> void:
	if not check_battle(backend,pending_guard).is_empty():return
	var proof: Dictionary=pending_guard.arrival
	var record: Dictionary=_battles[int(proof.serial)]
	_queue_warp(backend,record.npc,str(pending_guard.get("warp","")),Policy.battle_mark(Policy.source(record.npc)),Policy.battle_stage(Policy.source(record.npc)))
	_battles.erase(int(proof.serial))

func blocked_guard_items(pending_guard: Dictionary) -> Array:
	var proof: Dictionary=pending_guard.get("arrival",{})
	var record: Dictionary=_battles.get(int(proof.get("serial",-1)),{})
	if record.is_empty() or proof!=record.proof or str(proof.npc_id)!=str(pending_guard.get("npc_id","")) or str(proof.warp)!=str(pending_guard.get("warp","")):return []
	return Policy.blocked_guard_items(pending_guard)

func _queue_warp(backend, npc: Dictionary, raw: String, mark: String="", stage: String="") -> void:
	if raw.is_empty():return
	var parts: PackedStringArray=raw.split(",")
	if parts.size()!=3:return
	for value in parts:
		if not value.is_valid_int():return
	var target: int=int(parts[0])
	var target_scope: String=Policy.scope(target)
	var approach: String=Policy.approach_root(Policy.source(npc),target)
	if target_scope.is_empty() and approach.is_empty():return
	var origin: int=int(backend.automation.position_map)
	if approach.is_empty() and (target_scope!=_scope or not _at_authority(backend)):
		if not Policy.script_root(Policy.source(npc),target):return
	var cell: Vector2i=backend.automation.position_cell
	_warp={"epoch":_epoch,"from_map":origin,"from_cell":[cell.x,cell.y],"to_map":target,"to_cell":[int(parts[1]),int(parts[2])],"mark":mark,"stage":stage,"approach":approach}

## Public entry pockets do not turn the whole outdoor map into a quest scope.
## Only a reviewed saved script Warp or an already legitimate original return
## portal can start this memory; coordinates alone never start an approach.
func _begin_approach(name: String, map_id: int, cell: Vector2i, source_landing: bool=false) -> void:
	_invalidate()
	_approach={"name":name,"epoch":_epoch,"map_id":map_id,"cell":[cell.x,cell.y],"source_landing":source_landing}

func _has_approach(backend, name: String) -> bool:
	return not _approach.is_empty() and str(_approach.name)==name and int(_approach.epoch)==_epoch and int(_approach.map_id)==int(backend.automation.position_map) and _point(_approach.cell)==backend.automation.position_cell

func _continue_approach(backend, from_map: int, from_cell: Vector2i, to_map: int, to_cell: Vector2i) -> bool:
	if _approach.is_empty() or int(_approach.epoch)!=_epoch or int(_approach.map_id)!=from_map or _point(_approach.cell)!=from_cell or from_map!=to_map:return false
	if not Policy.approach_cell(str(_approach.name),to_map,to_cell) or not _walk_step(backend,from_map,from_cell,to_cell,bool(_approach.source_landing)):return false
	# A source portal must be taken, not walked through to launder continuity.
	if backend.quest_helper.places.links(from_map).has(from_cell) and not bool(_approach.source_landing):return false
	_approach.cell=[to_cell.x,to_cell.y]
	_approach.source_landing=false
	return true

func _at_authority(backend) -> bool:
	return not _scope.is_empty() and _scope==Policy.scope(int(backend.automation.position_map)) and _map==int(backend.automation.position_map) and _cell==backend.automation.position_cell

func _portal(backend, from_map: int, from_cell: Vector2i, to_map: int, to_cell: Vector2i, reviewed_landing: bool=false) -> bool:
	var link: Dictionary=backend.quest_helper.places.links(from_map).get(from_cell,{})
	if link.is_empty() or bool(link.get("disabled",false)) or int(link.get("to_map",-1))!=to_map or _point(link.get("target",[]))!=to_cell:return false
	# Scenic script-gate substitutions cannot become route proof. Adult's
	# original level gate is the existing explicitly validated portal exception.
	if link.has("gate_source") and str(link.gate_source)!="genout/wpm_10202_31_13":return false
	if int(backend.session._profile.get("player",{}).get("level",0))<int(link.get("requires_level",0)):return false
	if bool(link.get("requires_travel_pass",false)) and not backend.session.has_travel_pass():return false
	if link.has("requires_time") and not WorldClock.allows(str(link.requires_time),WorldClock.hour()):return false
	if reviewed_landing:
		var data: Dictionary=_map_data(backend,to_map)
		return not data.is_empty() and _floor(data,{},to_cell)
	return _walkable(backend,to_map,to_cell)

func _map_data(backend, map_id: int) -> Dictionary:
	var path: String=backend.quest_helper.places.file(map_id)
	if backend.quest_helper.places.info(map_id).is_empty() or not FileAccess.file_exists(path):return {}
	if not _maps.has(map_id):
		var data: Dictionary=MapFile.load_map(path)
		if data.is_empty():return {}
		_maps[map_id]=data
	return _maps[map_id]

func _npc_cells(backend, map_id: int) -> Dictionary:
	var catalog=backend.quest_catalog
	var signature: Array=[hash(catalog.npc_overrides),hash(catalog.enabled_events),catalog.npcs.size(),catalog.service_npcs.size()]
	if signature!=_block_signature:
		_block_cache.clear()
		for npc in catalog.active_npcs():
			var id: int=int(npc.map_id)
			if not _block_cache.has(id):_block_cache[id]={}
			_block_cache[id][_point(npc.cell)]=true
		_block_signature=signature
	return _block_cache.get(map_id,{})

func _walkable(backend, map_id: int, cell: Vector2i) -> bool:
	var data: Dictionary=_map_data(backend,map_id)
	if data.is_empty() or cell.x<0 or cell.y<0 or cell.x>=int(data.width) or cell.y>=int(data.height):return false
	if int(data.blocked[cell.y*int(data.width)+cell.x])!=0:return false
	return not _npc_cells(backend,map_id).has(cell)

func _walk_step(backend, map_id: int, start: Vector2i, finish: Vector2i, source_landing: bool=false) -> bool:
	var delta: Vector2i=finish-start
	if maxi(absi(delta.x),absi(delta.y))!=1 or not _walkable(backend,map_id,finish):return false
	if not _walkable(backend,map_id,start):
		var data: Dictionary=_map_data(backend,map_id)
		if not source_landing or data.is_empty() or not _floor(data,{},start):return false
	if delta.x!=0 and delta.y!=0:
		return _walkable(backend,map_id,start+Vector2i(delta.x,0)) and _walkable(backend,map_id,start+Vector2i(0,delta.y))
	return true

func _same_room(backend, map_id: int, start: Vector2i, finish: Vector2i) -> bool:
	var data: Dictionary=_map_data(backend,map_id)
	if data.is_empty():return false
	var npcs: Dictionary=_npc_cells(backend,map_id)
	var links: Dictionary=backend.quest_helper.places.links(map_id)
	var signature: Array=[hash(data.blocked),hash(npcs),hash(links)]
	if not _rooms.has(map_id) or _rooms[map_id].signature!=signature:
		var labels: Dictionary={}
		var serial: int=0
		for y in range(int(data.height)):
			for x in range(int(data.width)):
				var seed:=Vector2i(x,y)
				if labels.has(seed) or links.has(seed) or not _floor(data,npcs,seed):continue
				serial+=1
				var queue: Array[Vector2i]=[seed]
				labels[seed]=serial
				var cursor: int=0
				while cursor<queue.size():
					var point: Vector2i=queue[cursor];cursor+=1
					for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						var next: Vector2i=point+delta
						if labels.has(next) or links.has(next) or not _floor(data,npcs,next):continue
						labels[next]=serial;queue.append(next)
		_rooms[map_id]={"signature":signature,"labels":labels}
	var labels: Dictionary=_rooms[map_id].labels
	var first: int=_room_at(data,npcs,labels,links,start)
	return first>=0 and first==_room_at(data,npcs,labels,links,finish)

func _portal_approach(backend, map_id: int, member: Vector2i, portal: Vector2i) -> bool:
	var links: Dictionary=backend.quest_helper.places.links(map_id)
	if not links.has(portal):return false
	var data: Dictionary=_map_data(backend,map_id)
	if data.is_empty() or not _floor(data,{},portal):return false
	if member==portal:return true
	# Adjacent original source portals (the two time-cave doors) are each
	# endpoints, not an intervening portal traversed to reach this one.
	if links.has(member) and absi(member.x-portal.x)+absi(member.y-portal.y)==1 and _floor(data,{},member):return true
	# A genuine portal can touch several disconnected components. A follower
	# needs a path to its source from its own side, not a unique global label.
	_same_room(backend,map_id,member,portal)
	var labels: Dictionary=_rooms[map_id].labels
	var room: int=_room_at(data,_npc_cells(backend,map_id),labels,links,member)
	if room<0:return false
	for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if int(labels.get(portal+delta,-1))==room:return true
	return false

func _expire_marks(backend, map_id: int, cell: Vector2i) -> void:
	for mark in _marks.keys():
		var allowed: bool=false
		for region in Policy.mark_regions(str(mark)):
			if int(region[0])!=map_id:continue
			var anchor: Vector2i=Vector2i(int(region[1]),int(region[2]))
			# Reaching an original portal endpoint is not leaving its source
			# room yet. The actual Warp separately checks the destination region.
			if _same_room(backend,map_id,anchor,cell) or _portal_approach(backend,map_id,anchor,cell):allowed=true;break
		if not allowed:_marks.erase(mark)

static func _floor(data: Dictionary, npcs: Dictionary, cell: Vector2i) -> bool:
	return cell.x>=0 and cell.y>=0 and cell.x<int(data.width) and cell.y<int(data.height) and not npcs.has(cell) and int(data.blocked[cell.y*int(data.width)+cell.x])==0

static func _room_at(data: Dictionary, npcs: Dictionary, labels: Dictionary, links: Dictionary, cell: Vector2i) -> int:
	if labels.has(cell):return int(labels[cell])
	if not links.has(cell) or not _floor(data,{},cell):return -1
	# An actual portal may share its source cell with its original gate NPC.
	# Resolve only that endpoint; ordinary NPC cells remain excluded from BFS.
	var neighbours: Dictionary={}
	for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if labels.has(cell+delta):neighbours[labels[cell+delta]]=true
	return int(neighbours.keys()[0]) if neighbours.size()==1 else -1

static func _point(value) -> Vector2i:
	if not value is Array or value.size()!=2:return Vector2i(-1,-1)
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or float(coordinate)!=floor(float(coordinate)):return Vector2i(-1,-1)
	return Vector2i(int(value[0]),int(value[1]))
