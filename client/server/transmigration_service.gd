extends RefCounted
## Server-only preview state; no client-provided inheritance, reward or proof.
const KIND := "original_transmigration"
const NPC_ID := "777/ten.arg@32021:31:28"
const CLOSED := "人物转生第三阶段尚未开放；本次不会扣除宠物或改变属性。"
const Candidate=preload("res://server/transmigration_candidate.gd")
const Rules=preload("res://server/transmigration_rules.gd")
const Session=preload("res://server/game_session.gd")
var pending:Dictionary={}
var serial:=0
var reward_rng:=RandomNumberGenerator.new()
func _init()->void:reward_rng.randomize()
func reset()->void:pending.clear()
func _error(reason:String)->Dictionary:return {"ok":false,"reason":reason}
func _npc(b)->Dictionary:
 var n:Dictionary=b.original_quests.npc_by_id(NPC_ID)
 if n.get("kind")!=KIND or n.get("handler")!="Transmigration" or n.get("source_script")!="777/ten.arg" or n.get("service_id")!="777/ten.arg":return {}
 if int(n.get("map_id",-1))!=32021 or n.get("cell",[]).size()!=2:return {}
 if float(n.cell[0])!=31.0 or float(n.cell[1])!=28.0:return {}
 if n.get("transmigration",{}).get("rules")!=Candidate.State.RULES:return {}
 return n
func _admission(b,n:Dictionary)->String:
 if n.is_empty():return CLOSED
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.quest_auto.running or b.stationary.running:return "请先结束战斗或自动活动，再与精灵王交谈。"
 if b.quest_visit_guard.is_valid():
  var party:String=str(b.quest_visit_guard.call())
  if not party.is_empty():return party
 if not b.original_quests.allowed(b,n):return "请沿原路线走到精灵王身边。"
 var reason:String=b.quest_arrival.check_action(b,n,{},"SERVICE")
 if not reason.is_empty():return reason
 return Candidate.State.continuation_error(b.session._profile)
func command(b,c:Dictionary)->Dictionary:
 var n:=_npc(b)
 if n.is_empty():return _error(CLOSED)
 var action:Variant=c.get("action")
 if not action is String or action not in ["preview","confirm","cancel"]:return _error("转生操作无效。")
 var allowed:Array=["type","action","seq","client","_quest_connection"]+["npc_id","pet_ids"] if action=="preview" else ["type","action","seq","client","_quest_connection","token"]
 for key in c:
  if key not in allowed:return _error("转生请求包含不允许的字段。")
 if action=="preview":
  if c.get("npc_id")!=NPC_ID or not c.get("pet_ids",[]) is Array:return _error("转生人物或祭品选择无效。")
  return preview(b,n,c.get("pet_ids",[]))
 if not c.get("token") is String or pending.is_empty() or c.token!=pending.token:return _error("转生确认已过期，请重新与精灵王交谈。")
 if action=="cancel":
  pending.clear()
  return {"ok":true,"closed":true}
 return confirm(b,n)
func open(b,n:Dictionary)->Dictionary:
 if n!=_npc(b):return _error(CLOSED)
 return preview(b,n,[])
func preview(b,n:Dictionary,ids:Array)->Dictionary:
 var reason:=_admission(b,n)
 if not reason.is_empty():return _error(reason)
 var before:Dictionary=b.session.snapshot()
 if not b.session._valid_profile(before):return _error("人物存档未通过完整验证，不能转生。")
 var count:int=int(before.player.transmigration)+1
 var reward:=Rules.reward_for(before.original_savepoint_bits,count)
 if not reward.ok:return reward
 var definition:Dictionary=b.quest_catalog.reward_pets.get(str(reward.enemy_id),{})
 if definition.is_empty() or not Session.TroopArt.can_render([{"sprite":int(definition.get("sprite",0))}]):return _error("原奖励宠物来源或图像尚未导入。")
 # The unexposed seed is retained across successive previews of unchanged
 # state, including UID changes. Preview never reveals random growth grades.
 var seed_value:int=int(pending.seed) if pending.get("before",{})==before and pending.has("seed") else reward_rng.randi()
 serial+=1
 var token:="rebirth-%d-%d-%d"%[get_instance_id(),Time.get_ticks_usec(),serial]
 var built:=Candidate.build(before,ids,definition,seed_value,token,Session.PET_CAPACITY)
 if not built.ok:return built
 if not b.session._valid_profile(built.profile):return _error("转生候选存档未通过完整验证。")
 var proof:Dictionary=b.quest_arrival.action_context(b,n,{},"SERVICE")
 if proof.is_empty():return _error("本次没有沿原路线完成转生试炼，请重新挑战。")
 var sacrifices:Array=[]
 for index in built.selected.indices:
  var pet:Dictionary=before.pets[index]
  sacrifices.append({"pet_id":pet.pet_id,"template_id":int(str(pet.species).trim_prefix("original_")),"name":pet.name,"level":pet.level})
 pending={"token":token,"before":before.duplicate(true),"rev":b.rev,"proof":proof,"seed":seed_value,"candidate":built.profile.duplicate(true),"npc":n.duplicate(true)}
 return {"ok":true,"transmigration":{"token":token,"npc_id":NPC_ID,"new_count":count,"quest_count":built.quest_count,"equation":built.inherited.equation,"base_stats":built.inherited.base_stats.duplicate(),"stat_points":built.inherited.stat_points,"sacrifices":sacrifices,"reward":{"enemy_id":reward.enemy_id,"template_id":reward.template_id},"location":reward.location.duplicate(),"warning":"确认后消耗所选随身宠物，等级重置为1，按原规则继承属性并返回出生村。新轮任务旗标按原版清留；END53奖励未开放。"}}
func confirm(b,n:Dictionary)->Dictionary:
 var reason:=_admission(b,n)
 if not reason.is_empty():return _error(reason)
 if n!=pending.npc or int(b.rev)!=int(pending.rev) or b.session.snapshot()!=pending.before:return _error("人物状态已改变，请重新预览转生。")
 reason=b.quest_arrival.check_action_context(b,pending.proof)
 if not reason.is_empty():return _error(reason)
 # No await or external callback between the final proof check and the atomic
 # candidate write. Failure retains the token, frozen profile and reward seed.
 var candidate:Dictionary=pending.candidate
 if not b.session.commit_transmigration_candidate(candidate,b.save_path):return _error("save_failed")
 var reply:Dictionary={"ok":true,"closed":true,"transaction_id":pending.token,"new_count":candidate.player.transmigration,"location":candidate.location.duplicate()}
 b.last_saved_payload=JSON.stringify(b.session.snapshot())
 b.quest_arrival.consume_action_context(pending.proof)
 after_commit(b,candidate)
 return reply

## Shared post-save synchronization for both admission policies.
func after_commit(b,candidate:Dictionary)->void:
 pending.clear()
 b.quick_transmigration.reset()
 b.original_quests.pending.clear()
 _reset_round_npcs(b)
 b.quest_helper.cached_key="";b.quest_helper.cached_snapshot={}
 var settings:Dictionary=b.automation.profile_settings()
 for key in ["capture_pet","capture_pet_id"]:b.automation.settings[key]=settings[key]
 if not candidate.pets.any(func(p):return str(p.pet_id)==b.automation.training_pet_id):b.automation.training_pet_id=""
 var location:Dictionary=candidate.location
 b.automation.position_changed(int(location.map_id),Vector2i(int(location.x),int(location.y)),b.automation.position_map!=int(location.map_id),"project")
 b._emit({"type":"position","map_id":int(location.map_id),"cell":[int(location.x),int(location.y)],"client":""})
 b.publish()
func _reset_round_npcs(b)->void:
 var state=b.original_quests.npc_state
 var changed:=false
 for n in b.quest_catalog.npcs:
  var id:String=str(n.get("id",""))
  if not state.records.has(id):continue
  # Only reset per-character task cooldown/move state. Timeman visuals and
  # independently sampled birth positions are not quest progression.
  var task:bool=n.get("events",[]).any(func(e):return int(e) not in Rules.KEEP_END)
  if not task:continue
  var entry:Dictionary=state.records[id]
  if entry.has("dead_until"):entry.erase("dead_until");changed=true
  if entry.has("counter"):
   for key in ["counter","map_id","cell"]:entry.erase(key)
   changed=true
  if entry.is_empty():state.records.erase(id)
 if changed:state.version+=1
