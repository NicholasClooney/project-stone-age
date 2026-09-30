extends RefCounted
## LAN phase 3 (docs/development/lan-profiles.md): 组队 on the map. The
## profile hub (server/profile_hub.gd) owns one of these and hands it plain
## profile entries, as it does server/presence.gd, so this file holds no
## nodes, sockets or clocks.
##
## The original's rules (gmsv char/char_party.c, char/char_walk.c,
## map/map_warppoint.c):
## - You join the player standing on the cell in front of you (one cell in
##   the direction you face). If that player is a member, you join their
##   leader, who must then be within one cell of you. The leader must not be
##   fighting and must have the 组队 switch on (CHAR_ISPARTY). A party holds
##   CHAR_PARTYMAX 5 players, the leader included.
## - A member leaving leaves; the leader leaving disbands the party, and so
##   does the leader logging out (CHAR_DischargeParty).
## - When the leader takes a step, each member in turn takes one step
##   towards the cell the one before them stood on before the step, so the
##   party walks in a line. A warp takes every member to the leader's
##   destination cell.
## The leader's 踢出 (kick a member) is not in char_party.c; it is ours.
##
## Profile entries passed in: {id, name, level, map (int, -1 unknown), cell
## (Vector2i), battle (bool), auto (bool: automation running), connections}.

const MAX_MEMBERS := 5
## As server/presence.gd and the client's GameScene: facing = (index + 4) % 8.
const DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]

## id -> false once that player turns the 组队 switch off. The switch starts
## on (the original starts it off; here friends group without a detour
## through 设置). Kept for as long as the server runs; not in the save.
var accept: Dictionary = {}
## leader id -> [leader id, member id, ...] in joining order.
var parties: Dictionary = {}
## member or leader id -> leader id.
var _leader: Dictionary = {}

## The cell in front of `cell` for a facing (0..7).
static func front(cell: Vector2i, facing: int) -> Vector2i:
	return cell+DIRECTIONS[(posmod(facing,8)+4)%8]

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

func leader_of(id: String) -> String:
	return str(_leader.get(id,""))

func in_party(id: String) -> bool:
	return _leader.has(id)

func is_leader(id: String) -> bool:
	return in_party(id) and leader_of(id)==id

## In a party and not its leader: follows, cannot walk or meet enemies.
func is_member(id: String) -> bool:
	return in_party(id) and leader_of(id)!=id

## The party's ids, leader first; [] when `id` is in none.
func members(id: String) -> Array:
	return parties.get(leader_of(id),[]).duplicate()

func set_accept(id: String, on: bool) -> void:
	if on:accept.erase(id)
	else:accept[id] = false

func accepts(id: String) -> bool:
	return bool(accept.get(id,true))

## `joiner` joins the player in front of it (facing 0..7). `target`, when
## given, picks among several eligible parties on that cell (the original
## asks 「和谁组成团队呢？」); otherwise the first one is taken. Returns {ok,
## reason} or {ok, leader, members, created}.
func join(joiner_id: String, facing: int, profiles: Array, target: String = "") -> Dictionary:
	var by_id := {}
	for profile in profiles:by_id[str(profile.id)] = profile
	var joiner: Dictionary = by_id.get(joiner_id,{})
	if joiner.is_empty() or int(joiner.get("map",-1))<0:return _no("还不在地图上，暂时不能组队。")
	if in_party(joiner_id):return _no("已经在队伍里了。")
	if bool(joiner.get("battle",false)):return _no("战斗中不能组队。")
	if bool(joiner.get("auto",false)):return _no("请先停止自动练级、自动抓宠或找宠再组队。")
	var at := front(joiner.cell,facing)
	var found := false
	var eligible: Array = []
	var why := "无法加入团队。"
	for profile in profiles:
		var id := str(profile.id)
		if id==joiner_id or profile.get("connections",[]).is_empty() or int(profile.map)!=int(joiner.map) or profile.cell!=at:continue
		found = true
		var leader_id := leader_of(id) if in_party(id) else id
		var leader: Dictionary = by_id.get(leader_id,{})
		if leader.is_empty() or leader_id in eligible:continue
		if int(leader.map)!=int(joiner.map) or distance(leader.cell,joiner.cell)>1:continue
		if bool(leader.get("battle",false)):
			why = "对方正在战斗，无法加入团队。"
			continue
		if not accepts(leader_id):
			why = "对方没有打开组队开关，无法加入团队。"
			continue
		if bool(leader.get("auto",false)):
			why = "对方正在自动练级或找宠，无法加入团队。"
			continue
		if parties.get(leader_id,[leader_id]).size()>=MAX_MEMBERS:
			why = "对方的队伍已满（最多 %d 人）。" % MAX_MEMBERS
			continue
		eligible.append(leader_id)
	if eligible.is_empty():return _no(why if found else "面前没有其他玩家。")
	var chosen: String = target if target in eligible else str(eligible[0])
	var created := not parties.has(chosen)
	if created:
		parties[chosen] = [chosen]
		_leader[chosen] = chosen
	parties[chosen].append(joiner_id)
	_leader[joiner_id] = chosen
	return {"ok":true,"leader":chosen,"members":parties[chosen].duplicate(),"created":created}

## `id` leaves its party. A leader leaving disbands it. Returns {ok, reason}
## or {ok, leader, left: [ids no longer in a party], disbanded, members: the
## party after (empty when disbanded)}.
func leave(id: String) -> Dictionary:
	if not in_party(id):return _no("不在队伍里。")
	var leader_id := leader_of(id)
	if leader_id==id:return disband(id)
	var party: Array = parties[leader_id]
	party.erase(id)
	_leader.erase(id)
	if party.size()<=1:
		# The original: a leader with nobody left is no leader any more.
		parties.erase(leader_id)
		_leader.erase(leader_id)
		return {"ok":true,"leader":leader_id,"left":[id,leader_id],"disbanded":true,"members":[]}
	return {"ok":true,"leader":leader_id,"left":[id],"disbanded":false,"members":party.duplicate()}

## The leader removes a member.
func kick(leader_id: String, member_id: String) -> Dictionary:
	if not is_leader(leader_id):return _no("只有队长可以踢出队员。")
	if member_id==leader_id or leader_of(member_id)!=leader_id:return _no("这个人不在你的队伍里。")
	return leave(member_id)

func disband(leader_id: String) -> Dictionary:
	if not is_leader(leader_id):return _no("只有队长可以解散队伍。")
	var party: Array = parties[leader_id]
	parties.erase(leader_id)
	for id in party:_leader.erase(id)
	return {"ok":true,"leader":leader_id,"left":party.duplicate(),"disbanded":true,"members":[]}

## The leader moved from (old_map, old_cell) to (new_map, new_cell). Returns
## where each member goes: [[id, map, cell (Vector2i), map_changed], ...].
## `positions` is id -> [map, cell] for the members now.
##
## A step on the same map: each member steps one cell towards where the one
## before them stood before this step (char_walk.c). A warp, a map change or
## a jump of more than one cell: every member goes to the leader's cell
## (map_warppoint.c).
func follow(leader_id: String, old_map: int, old_cell: Vector2i, new_map: int, new_cell: Vector2i, positions: Dictionary) -> Array:
	if not is_leader(leader_id):return []
	if old_map==new_map and old_cell==new_cell:return []
	var moves: Array = []
	var walking := old_map==new_map and distance(old_cell,new_cell)==1
	var end := old_cell
	for id in parties[leader_id].slice(1):
		var at: Array = positions.get(id,[-1,Vector2i.ZERO])
		var map_id := int(at[0])
		var cell: Vector2i = at[1]
		if not walking or map_id!=new_map:
			if map_id!=new_map or cell!=new_cell:moves.append([id,new_map,new_cell,map_id!=new_map])
			continue
		var start := cell
		if start!=end:
			var step := Vector2i(signi(end.x-start.x),signi(end.y-start.y))
			moves.append([id,new_map,start+step,false])
		end = start
	return moves

## What one player's devices are told (the `party` event's fields).
func view(id: String, by_id: Dictionary) -> Dictionary:
	var result := {"accept":accepts(id),"leader":leader_of(id),"members":[],"battle":false}
	for member in members(id):
		var profile: Dictionary = by_id.get(member,{})
		result.members.append({"id":member,"name":str(profile.get("name","")),"lv":int(profile.get("level",1))})
	var leader: Dictionary = by_id.get(leader_of(id),{})
	result.battle = bool(leader.get("battle",false)) and is_member(id)
	return result

static func _no(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}
