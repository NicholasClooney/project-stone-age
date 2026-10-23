extends RefCounted
## Public project convenience, separate from the original king's admission.
const Candidate=preload("res://server/transmigration_candidate.gd")
const Rules=preload("res://server/transmigration_rules.gd")
const Session=preload("res://server/game_session.gd")
var pending:Dictionary={}
var serial:=0
var reward_rng:=RandomNumberGenerator.new()
func _init()->void:reward_rng.randomize()
func reset()->void:pending.clear()
func _error(reason:String)->Dictionary:return {"ok":false,"reason":reason}
func _admission(b)->String:
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.quest_auto.running or b.stationary.running:return "请先结束战斗或自动活动，再进行快速转生。"
 if b.quest_visit_guard.is_valid():
  var party:String=str(b.quest_visit_guard.call())
  if not party.is_empty():return party
 return Candidate.State.continuation_error(b.session._profile)
func command(b,c:Dictionary)->Dictionary:
 var action:Variant=c.get("action")
 if not action is String or action not in ["preview","confirm","cancel"]:return _error("转生操作无效。")
 var allowed:Array=["type","action","seq","client","_quest_connection"]
 allowed.append_array(["level_mode","bonus_quests","allocation_stats"] if action=="preview" else ["token"])
 for key in c:
  if key not in allowed:return _error("快速转生请求包含不允许的字段。")
 if action=="preview":return preview(b,{"level_mode":c.get("level_mode"),"bonus_quests":c.get("bonus_quests"),"allocation_stats":c.get("allocation_stats")})
 if not c.get("token") is String or pending.is_empty() or c.token!=pending.token:return _error("转生确认已过期，请重新预览。")
 if action=="cancel":
  pending.clear()
  return {"ok":true,"closed":true}
 return confirm(b)
func preview(b,options:Dictionary)->Dictionary:
 var reason:=_admission(b)
 if not reason.is_empty():return _error(reason)
 var before:Dictionary=b.session.snapshot()
 if not b.session._valid_profile(before):return _error("人物存档未通过完整验证，不能转生。")
 var count:int=int(before.player.transmigration)+1
 var reward:=Rules.reward_for(before.original_savepoint_bits,count)
 if not reward.ok:return reward
 var definition:Dictionary=b.quest_catalog.reward_pets.get(str(reward.enemy_id),{})
 if definition.is_empty() or not Session.TroopArt.can_render([{"sprite":int(definition.get("sprite",0))}]):return _error("原奖励宠物来源或图像尚未导入。")
 var seed_value:int=int(pending.seed) if pending.get("before",{})==before and pending.has("seed") else reward_rng.randi()
 serial+=1
 var token:="quick-rebirth-%d-%d-%d"%[get_instance_id(),Time.get_ticks_usec(),serial]
 var built:=Candidate.build_quick(before,options,definition,seed_value,token,Session.PET_CAPACITY)
 if not built.ok:return built
 if not b.session._valid_profile(built.profile):return _error("转生候选存档未通过完整验证。")
 pending={"token":token,"before":before.duplicate(true),"rev":b.rev,"options":options.duplicate(true),"seed":seed_value,"candidate":built.profile.duplicate(true)}
 var preview_data:Dictionary={"token":token,"new_count":count,"quest_count":built.quest_count,"equation":built.inherited.equation,"base_stats":built.inherited.base_stats.duplicate(),"stat_points":built.inherited.stat_points,"reward":{"enemy_id":reward.enemy_id,"template_id":reward.template_id,"name":str(definition.name)},"location":reward.location.duplicate(),"warning":"项目便利（作弊）：每次只转一转，免任务和守护兽且不扣宠；不补关联任务奖励。已有自由点与模拟新增点按所选属性分配后继承，原已配属性不洗点，旧任务与等级历史不补写。确认后等级重置为1、解除骑乘，任务旗标按原版清留并返回出生村，每转直接获得奖励宠（第五转机暴）。130级仅为超自然上限模拟；人物与宠物自然上限仍为120。"}
 for key in ["level_mode","actual_level","target_level","existing_points","gained_points","allocation","pre_base_stats"]:preview_data[key]=built[key]
 return {"ok":true,"quick_transmigration":preview_data}
func confirm(b)->Dictionary:
 var reason:=_admission(b)
 if not reason.is_empty():return _error(reason)
 if int(b.rev)!=int(pending.rev) or b.session.snapshot()!=pending.before:return _error("人物状态已改变，请重新预览转生。")
 var candidate:Dictionary=pending.candidate
 if not b.session.commit_transmigration_candidate(candidate,b.save_path):return _error("save_failed")
 var reply:Dictionary={"ok":true,"closed":true,"transaction_id":pending.token,"new_count":candidate.player.transmigration,"location":candidate.location.duplicate()}
 b.last_saved_payload=JSON.stringify(b.session.snapshot())
 b.transmigration.after_commit(b,candidate)
 return reply
