extends RefCounted
## Project policy B: one instance per character Backend; never serialized.
## Original NPC state was global. Here each character owns its own runtime state.
var clock:Callable=func():return int(Time.get_unix_time_from_system())
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
