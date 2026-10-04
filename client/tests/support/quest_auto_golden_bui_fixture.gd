extends RefCounted
## Pure planner fixture, not a legitimate-arrival or service transaction test.
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
class Arrival:
 extends RefCounted
 var valid:=true
 func has_arrival(_b,_map,_cell)->bool:return valid
 func check_action(_b,_npc,_branch,_phase)->String:return "" if valid else "no proof"
class Catalog:
 extends RefCounted
 var npcs:Array=[]
 var service_npcs:Array=[]
 var reward_pets:Dictionary={}
 func active_npcs()->Array:return npcs.duplicate(true)
var quest_catalog=Catalog.new()
var quest_arrival=Arrival.new()
var original_quests=preload("res://server/original_quests.gd").new()
var quest_helper:Dictionary={}
var automation:Dictionary={"position_map":800,"position_cell":Vector2i(29,21)}
var session:Dictionary={"_profile":{"player":{"level":35},"original_events":{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]},"original_items":[2752,2755],"pets":[]}}
func _init()->void:
 var data:=Sources.table()
 quest_catalog.npcs=data.get("npcs",[]).duplicate(true)
 quest_catalog.reward_pets={"14":data.get("reward_pet",{}).duplicate(true)}
 quest_helper={"places":preload("res://scripts/world_catalog.gd").new()}
func at(map_id:int,cell:Vector2i)->void:
 automation.position_map=map_id;automation.position_cell=cell
