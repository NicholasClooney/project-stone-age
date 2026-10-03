extends RefCounted
## Pinned NPCEnemy subsets: source troops, victory Warp or personal cooldown.
static func begin(rules, backend, npc: Dictionary, branch: Dictionary) -> Dictionary:
 if backend.quest_visit_guard.is_valid():
  var reason: String=str(backend.quest_visit_guard.call())
  if not reason.is_empty():return {"ok":false,"reason":reason}
 var ids:Array=[]
 if branch.has("guard"):
  var guard:Dictionary=branch.guard
  if int(guard.get("dieact",-1)) not in [0,1]:return {"ok":false,"reason":"尚未支持的守卫胜利动作。"}
  ids=guard.get("enemy_ids",[]).duplicate()
  var expected:PackedStringArray=str(branch.actions.Battle).split(",")
  if ids.is_empty() or ids.size()>10 or ids.size()!=expected.size():return {"ok":false,"reason":"未审计的守卫。"}
  for i in range(ids.size()):
   if int(ids[i])!=int(expected[i]) or not branch.get("combat_audit",{}).get("enemies",{}).has(str(int(ids[i]))):return {"ok":false,"reason":"守卫来源不匹配。"}
 else:
  var id:=int(branch.actions.Battle)
  if id not in [1001,1012,1013,1014,1015]:return {"ok":false,"reason":"未审计的守卫。"}
  ids=[id]
 var guard:Dictionary=branch.get("guard",{})
 for required in guard.get("required_items",[]):
  if not int(required) in backend.session._profile.original_items:return {"ok":false,"reason":str(branch.get("source_fields",{}).get("deniedmsg","缺少原守卫要求的道具。"))}
 var arrival_reason:String=backend.quest_arrival.check_action(backend,npc,branch,"BATTLE")
 if not arrival_reason.is_empty():return {"ok":false,"reason":arrival_reason}
 var arrival:Dictionary=backend.quest_arrival.battle_context(backend,npc,branch)
 var actors:Array=[]
 for id in ids:
  var actor:Dictionary=backend.encounter_catalog.actor(int(id),backend.encounter_rng)
  if actor.is_empty():return {"ok":false,"reason":"原守卫战资源尚未导入。"}
  actors.append(actor)
 var config:Dictionary=backend.session.start_wild_battle_config({"enemies":actors})
 if config.is_empty():return {"ok":false,"reason":"原守卫战资源尚未导入。"}
 backend.session._pending.quest_guard={"npc_id":npc.id,"warp":str(branch.actions.get("Warp","")),"guard":guard.duplicate(true),"arrival":arrival}
 rules.pending={}
 backend.open_battle(config)
 return {"ok":true,"closed":true}

static func settle_profile(backend, pending:Dictionary)->void:
 var guard:Dictionary=pending.get("guard",{})
 if int(guard.get("steal",0))==1:
  for item in guard.get("required_items",[]):backend.session.OriginalEquipment.remove(backend.session._profile,int(item))
 var warp:=str(pending.get("warp",""))
 if not warp.is_empty():warp_profile(backend.session._profile,warp)

static func committed(backend, pending:Dictionary)->void:
 var guard:Dictionary=pending.get("guard",{})
 if int(guard.get("dieact",1))==0:
  backend.original_quests.npc_state.defeated(str(pending.npc_id),int(guard.cooldown))
  backend.original_quests.refresh_npc_state()

static func warp_profile(profile: Dictionary, raw: String) -> void:
 var target:=raw.split(",")
 profile.location={"map_id":int(target[0]),"x":int(target[1]),"y":int(target[2])}

static func publish_warp(backend, raw: String) -> void:
 var target:=raw.split(",")
 var map_id:=int(target[0]);var cell:=Vector2i(int(target[1]),int(target[2]))
 backend.automation.position_changed(map_id,cell,map_id!=backend.automation.position_map,"script")
 backend._emit({"type":"position","map_id":map_id,"cell":[cell.x,cell.y],"client":""})
 backend.publish()
