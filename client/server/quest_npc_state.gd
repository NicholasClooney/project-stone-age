extends RefCounted
const Clock=preload("res://scripts/clock.gd")
## Project policy B: one instance per character Backend; never serialized.
## Original NPC state was global. Here each character owns its own runtime state.
var clock:Callable=func():return Clock.unix_time()
var records:Dictionary={}
var version:=0
func expire()->bool:
 var changed:=false
 var now:=int(clock.call())
 for id in records.keys():
  var entry:Dictionary=records[id]
  # C uses NowTime > death_time + time, not >=.
  if entry.has("dead_until") and now>int(entry.dead_until):
   entry.erase("dead_until");changed=true
   if entry.is_empty():records.erase(id)
 if changed:version+=1
 return changed
func snapshot()->Dictionary:
 var result:Dictionary={}
 for id in records:
  var entry:Dictionary=records[id]
  var public:Dictionary={}
  if entry.has("dead_until"):public.hidden=true
  if entry.has("time_mode"):public.time_mode=entry.time_mode
  if entry.has("map_id"):public.map_id=int(entry.map_id);public.cell=entry.cell.duplicate()
  if not public.is_empty():result[id]=public
 return result
func defeated(id:String,cooldown:int)->void:
 var entry:Dictionary=records.get(id,{}).duplicate(true)
 entry.dead_until=int(clock.call())+cooldown
 records[id]=entry;version+=1
func moved(id:String,destinations:Array)->void:
 if destinations.is_empty():return
 var entry:Dictionary=records.get(id,{}).duplicate(true)
 var next:=int(entry.get("counter",0))%destinations.size()
 var point:Array=destinations[next]
 entry.map_id=int(point[0]);entry.cell=[int(point[1]),int(point[2])]
 entry.counter=(next+1)%destinations.size()
 records[id]=entry;version+=1

# Source birth attempts are not quest transactions and never enter the save.
# An unsuccessful draw stays absent; the next server second retries one point.
var spawn_rng:=RandomNumberGenerator.new()
var spawn_attempts:Dictionary={}
func _init()->void:spawn_rng.randomize()
func spawn_areas(npcs:Array,enabled_events:Array)->bool:
 var changed:=false
 var now:=float(clock.call())
 for npc in npcs:
  if not npc.has("source_spawn") or not npc.get("events",[]).any(func(e):return int(e) in enabled_events):continue
  var id:=str(npc.id)
  if records.get(id,{}).has("map_id"):continue
  if spawn_attempts.has(id) and now<float(spawn_attempts[id])+1.0:continue
  spawn_attempts[id]=now
  var rule:Dictionary=npc.source_spawn
  var rect:Array=rule.rect
  var width:=int(rect[2])-int(rect[0])+1
  var area:=width*(int(rect[3])-int(rect[1])+1)
  var offset:=spawn_rng.randi_range(0,area-1)
  if str(rule.walkable).substr(offset,1)!="1":continue
  records[id]={"map_id":int(npc.map_id),"cell":[int(rect[0])+offset%width,int(rect[1])+int(offset/width)]}
  version+=1;changed=true
 return changed

func refresh_time_visuals(npcs:Array,enabled_events:Array)->bool:
 var mode:="main" if preload("res://server/original_world_clock.gd").after_at(preload("res://server/original_world_clock.gd").hour()) else "changed"
 var changed:=false
 for npc in npcs:
  if npc.get("handler","")!="TimeMan" or not npc.get("events",[]).any(func(e):return int(e) in enabled_events):continue
  var id:=str(npc.id)
  if records.get(id,{}).get("time_mode","")==mode:continue
  var entry:Dictionary=records.get(id,{}).duplicate(true)
  entry.time_mode=mode;records[id]=entry;changed=true
 if changed:version+=1
 return changed
