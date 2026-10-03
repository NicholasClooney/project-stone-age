extends SceneTree
const Catalog=preload("res://scripts/quest_catalog.gd")
const Helper=preload("res://server/quest_helper.gd")
# Old geometry consumed the full projection and filtered map_id in its loop.
# Substitution reproduces that old input without copying the new projection.
class FullCatalog extends "res://scripts/quest_catalog.gd":
 func active_npcs_on_map(_map_id:int)->Array:return active_npcs()
var failures:int=0
var actual=Catalog.new()
var old=FullCatalog.new()
var helper=Helper.new()
var reference=Helper.new()
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func compare(npc:Dictionary,label:String)->Dictionary:
 old.npc_overrides=actual.npc_overrides.duplicate(true)
 old.enabled_events=actual.enabled_events.duplicate()
 var near:Dictionary={}
 for mode in ["near","arrival"]:
  var expected:Dictionary=reference.geometric_destination({"quest_catalog":old},npc,mode)
  var result:Dictionary=helper.geometric_destination({"quest_catalog":actual},npc,mode)
  check(result==expected,label+" old/full versus map projection "+mode)
  check(helper.places.residents==reference.places.residents,label+" full world residents preserved "+mode)
  if mode=="near":near=result
 return near
func run()->void:
 var rows:Array=actual.active_npcs();var chosen:Dictionary={};var baseline:Dictionary={}
 var maps:Array=[]
 for npc in rows:
  if maps.size()>=12:break
  if int(npc.map_id) in maps:continue
  maps.append(int(npc.map_id))
  var result:Dictionary=compare(npc,"source "+str(npc.id))
  if chosen.is_empty() and not result.is_empty():chosen=npc;baseline=result
 check(not chosen.is_empty(),"source NPC has a safe unoccupied neighbour")
 compare({"id":"unknown-map","map_id":-909,"cell":[1,1]},"unknown map")
 var blocker:Dictionary={}
 for npc in rows:
  if str(npc.id)!=str(chosen.id) and not npc.has("source_spawn"):blocker=npc;break
 actual.npc_overrides[str(blocker.id)]={"map_id":int(chosen.map_id),"cell":baseline.cell.duplicate()}
 var blocked:Dictionary=compare(chosen,"personal override into destination")
 check(blocked!=baseline and (blocked.is_empty() or blocked.cell!=baseline.cell),"occupied original safe cell is excluded")
 actual.npc_overrides[str(blocker.id)].map_id=-909
 check(compare(chosen,"personal override moved out")==baseline,"moving blocker out restores source destination")
 actual.npc_overrides[str(blocker.id)].map_id=int(chosen.map_id)
 actual.npc_overrides[str(blocker.id)].hidden=true
 check(compare(chosen,"personal hidden blocker")==baseline,"hidden blocker does not occupy safe cell")
 actual.npc_overrides.clear()
 var spawned:Array=actual.npcs.filter(func(n):return n.has("source_spawn"))
 check(not spawned.is_empty(),"actual regional birth source exists")
 compare(chosen,"regional actor unborn")
 actual.npc_overrides[str(spawned[0].id)]={"map_id":int(chosen.map_id),"cell":baseline.cell.duplicate()}
 check(compare(chosen,"regional actor born at safe cell")!=baseline,"born regional NPC occupies safe cell")
 actual.npc_overrides.clear();actual.enabled_events.erase(46)
 compare(chosen,"water disabled with other source NPCs")
 print("QUEST GEOMETRY PROJECTION: %d failures"%failures);quit(1 if failures else 0)
