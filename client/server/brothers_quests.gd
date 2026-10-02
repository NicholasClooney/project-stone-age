extends RefCounted
## Only the pinned NPCEnemy dieact=1 and warpman subset used by these chains.
static func begin(rules, backend, npc: Dictionary, branch: Dictionary) -> Dictionary:
 if backend.quest_visit_guard.is_valid():
  var reason: String=str(backend.quest_visit_guard.call())
  if not reason.is_empty():return {"ok":false,"reason":reason}
 var id:=int(branch.actions.Battle)
 if id not in [1001,1012,1013,1014,1015]:return {"ok":false,"reason":"未审计的守卫。"}
 var actor:Dictionary=backend.encounter_catalog.actor(id,backend.encounter_rng)
 var config:Dictionary=backend.session.start_wild_battle_config({"enemies":[actor]})
 if config.is_empty():return {"ok":false,"reason":"原守卫战资源尚未导入。"}
 backend.session._pending.quest_guard={"npc_id":npc.id,"warp":str(branch.actions.Warp)}
 rules.pending={}
 backend.open_battle(config)
 return {"ok":true,"closed":true}

static func warp_profile(profile: Dictionary, raw: String) -> void:
 var target:=raw.split(",")
 profile.location={"map_id":int(target[0]),"x":int(target[1]),"y":int(target[2])}

static func publish_warp(backend, raw: String) -> void:
 var target:=raw.split(",")
 var map_id:=int(target[0]);var cell:=Vector2i(int(target[1]),int(target[2]))
 backend.automation.position_changed(map_id,cell,map_id!=backend.automation.position_map)
 backend._emit({"type":"position","map_id":map_id,"cell":[cell.x,cell.y],"client":""})
 backend.publish()
