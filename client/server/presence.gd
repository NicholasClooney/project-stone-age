extends RefCounted
## LAN phase 2 (docs/development/lan-profiles.md): who stands where, and the
## map's 一般频道 chat. The profile hub (server/profile_hub.gd) hands tick()
## and say() a plain list of the open profiles and emits what they return, so
## this file holds no nodes, sockets or clocks of its own.
##
## A profile appears to others while one of its devices is connected and its
## map is known (the walking client's report_position). Each connection sees
## the other profiles on its own profile's map: a `presence` event with
## full=true lists them all when it arrives on a map (or logs in), and later
## ones carry only what changed since that connection's last one (a cell, a
## mount, the 战斗中 mark) plus `left` for players who went away. Ticks are
## at most every TICK_MSEC and send nothing when nothing changed.
##
## Profile entries passed in: {id, name, level, look: {c, face, ride, rn},
## map (int, -1 unknown), cell (Vector2i), battle (bool), connections (Array),
## party (optional, LAN phase 3: the leader's id while in a 组队 party)}.

const TICK_MSEC := 150
## The 战斗中 mark stays this long after a battle closes, so back-to-back
## automatic battles do not make it flicker.
const BATTLE_HOLD_MSEC := 2000
## 一般频道: at most CHAT_MAX_CHARS characters, CHAT_BURST lines per
## CHAT_WINDOW_MSEC per character.
const CHAT_MAX_CHARS := 60
const CHAT_BURST := 3
const CHAT_WINDOW_MSEC := 5000
## Screen directions of a one-cell step, as the client's GameScene uses them;
## facing = (index + 4) % 8.
const DIRECTIONS := [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1)]

var _last_tick := -1
## id -> [map, cell] last seen, for facing.
var _where: Dictionary = {}
var _facing: Dictionary = {}
var _battle_until: Dictionary = {}
## connection -> {map, players: {id: entry}}: what that device was told.
var _seen: Dictionary = {}
## id -> [msec, ...] of recent chat lines.
var _said: Dictionary = {}
## Totals for tests and diagnostics.
var messages_sent := 0

## The facing a step from `from` to `to` gives (-1 when it is no step).
static func step_facing(from: Vector2i, to: Vector2i) -> int:
	var d := Vector2i(signi(to.x-from.x),signi(to.y-from.y))
	var index := DIRECTIONS.find(d)
	return -1 if index<0 else (index+4)%8

## What one player looks like to others.
func entry(profile: Dictionary, now: int) -> Dictionary:
	var id := str(profile.id)
	var cell: Vector2i = profile.cell
	var map_id := int(profile.map)
	var before: Array = _where.get(id,[])
	if not before.is_empty() and int(before[0])==map_id and before[1]!=cell:
		var facing := step_facing(before[1],cell)
		if facing>=0:_facing[id] = facing
	_where[id] = [map_id,cell]
	if bool(profile.get("battle",false)):_battle_until[id] = now+BATTLE_HOLD_MSEC
	var look: Dictionary = profile.get("look",{})
	return {"id":id,"name":str(profile.get("name","")),"lv":int(profile.get("level",1)),"c":str(look.get("c","100000")),"face":int(look.get("face",0)),"ride":int(look.get("ride",-1)),"rn":str(look.get("rn","")),"cell":[cell.x,cell.y],"f":int(_facing.get(id,4)),"b":now<int(_battle_until.get(id,-1)),"pt":str(profile.get("party",""))}

## Every connection's news since its last tick: [[connection, message], ...].
## Nothing before TICK_MSEC has passed since the last tick, unless forced.
func tick(now: int, profiles: Array, force: bool = false) -> Array:
	if not force and _last_tick>=0 and now-_last_tick<TICK_MSEC:return []
	_last_tick = now
	var visible: Array = []
	var entries: Dictionary = {}
	for profile in profiles:
		if profile.get("connections",[]).is_empty() or int(profile.map)<0:continue
		visible.append(profile)
		entries[str(profile.id)] = entry(profile,now)
	var out: Array = []
	for profile in profiles:
		for connection in profile.get("connections",[]):
			var message := _news(connection,profile,visible,entries)
			if not message.is_empty():out.append([connection,message])
	messages_sent += out.size()
	return out

func _news(connection, viewer: Dictionary, visible: Array, entries: Dictionary) -> Dictionary:
	var map_id := int(viewer.map)
	var others: Dictionary = {}
	if map_id>=0:
		for profile in visible:
			if str(profile.id)!=str(viewer.id) and int(profile.map)==map_id:others[str(profile.id)] = entries[str(profile.id)]
	var seen: Dictionary = _seen.get(connection,{})
	if seen.is_empty() or int(seen.map)!=map_id:
		_seen[connection] = {"map":map_id,"players":others}
		return {"type":"presence","v":1,"map_id":map_id,"full":true,"players":others.values()}
	var told: Dictionary = seen.players
	var changes: Array = []
	for id in others:
		var now_entry: Dictionary = others[id]
		if not told.has(id):
			changes.append(now_entry)
			continue
		var change := {"id":id}
		for key in now_entry:
			if now_entry[key]!=told[id].get(key):change[key] = now_entry[key]
		if change.size()>1:changes.append(change)
	var left: Array = []
	for id in told:
		if not others.has(id):left.append(id)
	seen.players = others
	if changes.is_empty() and left.is_empty():return {}
	var message := {"type":"presence","v":1,"map_id":map_id,"full":false,"players":changes}
	if not left.is_empty():message.left = left
	return message

## A connection closed, logged out or logged into another profile: it gets a
## full list again next time.
func forget(connection) -> void:
	_seen.erase(connection)

## One 一般频道 line from `speaker` (a profile entry). Returns {reply,
## deliveries: [[connection, message], ...]}: every device of every profile on
## the speaker's map hears it, the speaker's own included (`mine`).
## With `party` (the speaker's party ids, LAN phase 3) it is a 队伍频道 line
## instead: every device of those profiles hears it, on any map.
func say(now: int, speaker: Dictionary, profiles: Array, raw: String, party: Array = []) -> Dictionary:
	var text := clean(raw)
	var refused := func(reason: String) -> Dictionary:return {"reply":{"ok":false,"reason":reason},"deliveries":[]}
	if text.is_empty():return refused.call("说点什么吧。")
	if text.length()>CHAT_MAX_CHARS:return refused.call("一次最多说 %d 个字。" % CHAT_MAX_CHARS)
	var map_id := int(speaker.get("map",-1))
	if map_id<0 and party.is_empty():return refused.call("还不在地图上，暂时不能说话。")
	var id := str(speaker.id)
	var recent: Array = _said.get(id,[]).filter(func(time):return now-int(time)<CHAT_WINDOW_MSEC)
	if recent.size()>=CHAT_BURST:
		_said[id] = recent
		return refused.call("说话太快了，请 %d 秒后再说。" % ceili((CHAT_WINDOW_MSEC-(now-int(recent[0])))/1000.0))
	recent.append(now)
	_said[id] = recent
	var deliveries: Array = []
	for profile in profiles:
		if party.is_empty() and int(profile.get("map",-1))!=map_id:continue
		if not party.is_empty() and not str(profile.id) in party:continue
		for connection in profile.get("connections",[]):
			deliveries.append([connection,{"type":"chat","v":1,"channel":"一般" if party.is_empty() else "队伍","map_id":map_id,"id":id,"name":str(speaker.get("name","")),"text":text,"mine":str(profile.id)==id}])
	messages_sent += deliveries.size()
	return {"reply":{"ok":true,"text":text},"deliveries":deliveries}

## One line: surrounding spaces trimmed, control characters (line breaks,
## tabs) turned into spaces.
static func clean(raw: String) -> String:
	var result := ""
	for character in raw:
		result += " " if character.unicode_at(0)<32 or character.unicode_at(0)==127 else character
	return result.strip_edges()
