extends RefCounted
## Internal, pure candidate builder. No arrival proof, IO, or client dispatch.
const Rules=preload("res://server/transmigration_rules.gd")
const State=preload("res://server/transmigration_state.gd")
const Progression=preload("res://server/progression.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Loyalty=preload("res://server/loyalty.gd")

static func build(before:Dictionary,selected_ids:Array,reward_definition:Dictionary,seed_value:int,transaction_id:String,pet_capacity:int)->Dictionary:
 var reason:=State.continuation_error(before)
 if not reason.is_empty():return {"ok":false,"reason":reason}
 if int(before.player.level)<80:return {"ok":false,"reason":"人物等级需要达到80级。"}
 for event in [39,40,42,46]:
  if not Rules._flag(before.original_events.ended,event):return {"ok":false,"reason":"需要完成地、水、火、风四项试炼。"}
 var count:int=int(before.player.transmigration)+1
 var selected:=Rules.select_sacrifices(before.pets,count,selected_ids)
 if not selected.ok:return selected
 var quests:=Rules.quest_count(before.original_events)
 var inherited:=Rules.inherit(before.player.base_stats,before.rebirth.equation,before.player.level,count,quests)
 return _settle(before,selected,reward_definition,seed_value,transaction_id,pet_capacity,quests,inherited)

## Project convenience policy. Simulated levels/points exist only as formula
## inputs, never as an installed or saved intermediate player profile.
static func build_quick(before:Dictionary,options:Dictionary,reward_definition:Dictionary,seed_value:int,transaction_id:String,pet_capacity:int)->Dictionary:
 var reason:=State.continuation_error(before)
 if not reason.is_empty():return {"ok":false,"reason":reason}
 var mode:Variant=options.get("level_mode")
 var quests:Variant=options.get("bonus_quests")
 var stats:Variant=options.get("allocation_stats")
 if not mode is String or mode not in ["current","120","130"]:return {"ok":false,"reason":"请选择当前等级、120或130级模拟。"}
 if not Rules.integer(quests,0,20) or int(quests) not in [0,20]:return {"ok":false,"reason":"本轮任务加成只允许0或20。"}
 if not stats is Array or stats.is_empty() or stats.size()>4:return {"ok":false,"reason":"请至少选择一项加点属性。"}
 var seen:Dictionary={}
 for stat in stats:
  if not stat is String or stat not in Rules.STATS or seen.has(stat):return {"ok":false,"reason":"加点属性无效或重复。"}
  seen[stat]=true
 var actual:int=int(before.player.level)
 var target:int=actual if mode=="current" else int(mode)
 if target<actual:return {"ok":false,"reason":"模拟目标不能低于真实等级。"}
 if target<80:return {"ok":false,"reason":"当前等级不足80级，请选择120或130级模拟。"}
 var existing:int=int(before.player.stat_points)
 var gained:int=3*(target-actual)
 var points:int=existing+gained
 var base:Dictionary=before.player.base_stats.duplicate()
 var allocation:Array=[]
 var remainder:int=points%stats.size()
 for stat in Rules.STATS:
  if not seen.has(stat):continue
  var assigned:int=points/stats.size()
  if remainder>0:assigned+=1;remainder-=1
  allocation.append({"stat":stat,"points":assigned})
  base[stat]=int(base[stat])+100*assigned
 var inherited:=Rules.inherit(base,before.rebirth.equation,target,int(before.player.transmigration)+1,int(quests))
 var result:=_settle(before,{"ok":true,"indices":[],"pet_ids":[]},reward_definition,seed_value,transaction_id,pet_capacity,int(quests),inherited)
 if result.ok:result.merge({"level_mode":mode,"actual_level":actual,"target_level":target,"existing_points":existing,"gained_points":gained,"allocation":allocation,"pre_base_stats":base})
 return result

## Shared settlement receives only server policy results, never RPC fields.
static func _settle(before:Dictionary,selected:Dictionary,reward_definition:Dictionary,seed_value:int,transaction_id:String,pet_capacity:int,quests:int,inherited:Dictionary)->Dictionary:
 if transaction_id.is_empty() or transaction_id.length()>128:return {"ok":false,"reason":"转生事务身份无效。"}
 if pet_capacity<1 or before.pets.size()>pet_capacity:return {"ok":false,"reason":"随身宠物容量状态无效。"}
 if before.pets.size()-selected.indices.size()+1>pet_capacity:return {"ok":false,"reason":"宠物栏没有奖励宠物的空间，请先整理随身宠物。"}
 var count:int=int(before.player.transmigration)+1
 var reward:=Rules.reward_for(before.original_savepoint_bits,count)
 if not reward.ok:return reward
 if int(reward_definition.get("enemy_id",-1))!=int(reward.enemy_id) or int(reward_definition.get("template_id",-1))!=int(reward.template_id) or reward_definition.get("species")!="original_%d"%int(reward.template_id) or int(reward_definition.get("level",-1))!=1:return {"ok":false,"reason":"原奖励宠物来源不匹配。"}
 if not inherited.ok:return inherited
 var flags:=Rules.flags_after(before.original_events,count)
 if not flags.ok:return flags
 var candidate:=before.duplicate(true)
 candidate.player.transmigration=count
 candidate.player.level=1
 candidate.player.xp=0
 candidate.player.base_stats=inherited.base_stats.duplicate()
 candidate.player.allocated_stats={"vitality":0,"strength":0,"toughness":0,"dexterity":0}
 candidate.player.stat_points=inherited.stat_points
 candidate.player.erase("legacy_stat_offset")
 candidate.rebirth={"schema":State.SCHEMA,"rules":State.RULES,"history":"natural","equation":inherited.equation,"inherited_base":inherited.base_stats.duplicate(),"developer_base_delta":{"vitality":0,"strength":0,"toughness":0,"dexterity":0},"round_points":inherited.stat_points,"consumed_gm_points":int(before.rebirth.get("consumed_gm_points",0))+int(before.get("gm_bonus_points",0)),"last_transaction":transaction_id}
 candidate.gm_bonus_points=0
 candidate.original_events=flags.events
 candidate.location=reward.location.duplicate()
 Progression.refresh(candidate.player)
 candidate.player.hp=candidate.player.max_hp
 var indices:Array=selected.indices.duplicate()
 indices.sort();indices.reverse()
 for removed in indices:
  var uid:String=str(candidate.pets[removed].pet_id)
  candidate.pets.remove_at(removed)
  var active:int=int(candidate.active_pet)
  candidate.active_pet=-1 if active==removed else (active-1 if active>removed else active)
  var capture:Dictionary=candidate.get("automation_settings",{}).get("capture",{})
  var index:int=int(capture.get("pet",-1))
  if str(capture.get("pet_id",""))==uid or (str(capture.get("pet_id","")).is_empty() and index==removed):capture.pet_id="";capture.pet=-1
  elif index>removed:capture.pet=index-1
 candidate.ride_pet=-1
 for key in ["initial","weights","species","template_id","name","sprite","elements","size","modai","skill_slots"]:
  if not reward_definition.has(key):return {"ok":false,"reason":"原奖励宠物资料不完整。"}
 var pet:=Progression.species_actor(str(reward_definition.species),1,seed_value,[],reward_definition)
 if pet.is_empty():return {"ok":false,"reason":"原奖励宠物成长资料缺失。"}
 for key in ["species","template_id","name","sprite","elements","size","modai","skill_slots"]:
  if not reward_definition.has(key):return {"ok":false,"reason":"原奖励宠物资料不完整。"}
  pet[key]=reward_definition[key].duplicate(true) if reward_definition[key] is Array or reward_definition[key] is Dictionary else reward_definition[key]
 pet.merge({"level":1,"xp":0,"skill_unlocked":false,"favorite":false,"variable_ai":0,"original_end_event":0,"source_enemy_id":reward.enemy_id,"quest_reward_event":47+count,"pet_id":"pet-%d"%int(candidate.next_pet_id)})
 candidate.next_pet_id+=1
 candidate.pets.append(pet)
 var equipment:=Equipment.revalidate_after_transmigration(candidate,15)
 if not equipment.ok:return equipment
 candidate=equipment.profile
 # The Session applies effective equipment charm on ordinary refresh. Use the
 # same calculation without migrating equipment or touching the live profile.
 var owner:Dictionary=candidate.player.duplicate()
 owner.charm=clampi(int(owner.get("charm",60))+int(Equipment.mods(candidate).get("charm",0)),0,100)
 for companion in candidate.pets+candidate.get("pet_storage",[]):
  if companion.has("variable_ai"):Loyalty.refresh(companion,owner,count)
 return {"ok":true,"profile":candidate,"selected":selected,"reward":reward,"quest_count":quests,"inherited":inherited,"unequipped_uids":equipment.unequipped_uids}
