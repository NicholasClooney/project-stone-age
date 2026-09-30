extends RefCounted
## The other players on this device's map (LAN phase 2), as the server's
## `presence` and `chat` events describe them (server/presence.gd), plus where
## each one is drawn right now. No nodes: scripts/remote_players.gd draws it.
##
## Positions are in map cells. A player walks towards the last cell the
## server named at the local character's walking speed (one cell per
## STEP_TIME, diagonals as long as the local ones), faster when it has fallen
## more than CATCH_UP cells behind, and jumps when more than SNAP_CELLS away
## (a warp or 瞬移). The walking animation lingers WALK_LINGER seconds after
## arriving, since the next cell usually comes a moment later.

const STEP_TIME := 0.19
const CATCH_UP := 2.0
const SNAP_CELLS := 8.0
const WALK_LINGER := 0.3
const SPEECH_SECONDS := 5.0
## As server/presence.gd and GameScene.SCREEN_DIRECTIONS: facing = (i+4)%8.
const DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]

## The map the players are on (-1 before the first event).
var map_id := -1
## id -> {id, name, lv, c, face, ride, rn, cell: Vector2i, f, b,
## pos: Vector2, walking: bool, facing: int, idle: float,
## speech: String, speech_left: float}
var players: Dictionary = {}

## Applies one server event. Returns {spawned, changed, despawned} (ids).
func apply(message: Dictionary) -> Dictionary:
	var result := {"spawned":[],"changed":[],"despawned":[]}
	match str(message.get("type","")):
		"presence":
			var arrived := int(message.get("map_id",-1))
			if bool(message.get("full",false)) or arrived!=map_id:
				result.despawned = players.keys()
				players.clear()
				map_id = arrived
			for item in message.get("players",[]):
				var id := str(item.get("id",""))
				if id.is_empty():continue
				if players.has(id):
					_merge(players[id],item)
					result.changed.append(id)
				elif item.has("cell"):
					var player := {"id":id,"name":"","lv":1,"c":"100000","face":0,"ride":-1,"rn":"","f":4,"b":false,"walking":false,"idle":WALK_LINGER,"speech":"","speech_left":0.0}
					_merge(player,item)
					player.pos = Vector2(player.cell)
					player.facing = int(player.f)
					players[id] = player
					result.despawned.erase(id)
					result.spawned.append(id)
			for id in message.get("left",[]):
				if players.erase(str(id)):result.despawned.append(str(id))
		"chat":
			var id := str(message.get("id",""))
			if players.has(id):
				players[id].speech = str(message.get("text",""))
				players[id].speech_left = SPEECH_SECONDS
				result.changed.append(id)
	return result

func _merge(player: Dictionary, item: Dictionary) -> void:
	for key in item:
		if key=="cell":player.cell = Vector2i(int(item.cell[0]),int(item.cell[1]))
		else:player[key] = item[key]

## Moves every player `delta` seconds on towards its cell.
func step(delta: float) -> void:
	for player in players.values():
		advance(player,delta)

static func advance(player: Dictionary, delta: float) -> void:
	if float(player.speech_left)>0:
		player.speech_left = maxf(0.0,float(player.speech_left)-delta)
		if player.speech_left<=0:player.speech = ""
	var target := Vector2(player.cell)
	var offset: Vector2 = target-player.pos
	var distance := offset.length()
	if distance<=0.0001:
		player.idle = float(player.idle)+delta
		player.walking = float(player.idle)<WALK_LINGER
		if not player.walking:player.facing = int(player.f)
		return
	if distance>SNAP_CELLS:
		player.pos = target
		player.idle = WALK_LINGER
		player.walking = false
		player.facing = int(player.f)
		return
	var speed := 1.0/STEP_TIME*maxf(1.0,distance/CATCH_UP)
	var moved := minf(distance,speed*delta)
	player.pos = player.pos+offset/distance*moved
	player.idle = 0.0
	player.walking = true
	player.facing = facing_towards(offset,int(player.facing))

## The facing of a move along `offset` (its signs), else `current`.
static func facing_towards(offset: Vector2, current: int) -> int:
	var d := Vector2i(signi(roundi(offset.x*1000)),signi(roundi(offset.y*1000)))
	var index := DIRECTIONS.find(d)
	return current if index<0 else (index+4)%8

func clear() -> void:
	players.clear()
	map_id = -1
