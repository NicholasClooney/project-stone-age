extends RefCounted
## Versioned persistence, not the inheritance formula or an arrival permission.
const SCHEMA := 1
const RULES := "original-1to5-anson20-v1"
const STATS := ["vitality","strength","toughness","dexterity"]
const COMMON := ["schema","rules","history"]
const FIELDS := ["schema","rules","history","equation","inherited_base","developer_base_delta","round_points","consumed_gm_points","last_transaction"]

static func integer(value:Variant,low:int,high:int)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=low and value<=high

static func zero()->Dictionary:
 return {"schema":SCHEMA,"rules":RULES,"history":"zero","equation":0,"inherited_base":{},"developer_base_delta":{},"round_points":0,"consumed_gm_points":0,"last_transaction":""}

static func migrate(profile:Dictionary)->void:
 # Caller validates the old schema first. Never derive history from today's level.
 if profile.has("rebirth"):return
 if not profile.player.has("transmigration"):profile.player.transmigration=0
 profile.rebirth=zero() if int(profile.player.transmigration)==0 else {"schema":SCHEMA,"rules":RULES,"history":"legacy_unknown"}

static func valid(profile:Dictionary)->bool:
 var player:Variant=profile.get("player")
 if not player is Dictionary or player.has("transmigration_equation"):return false
 if not integer(player.get("transmigration",0),0,2147483647):return false
 if int(profile.get("version",0))<7:
  return not profile.has("rebirth")
 if not player.has("transmigration") or not profile.get("rebirth") is Dictionary:return false
 var state:Dictionary=profile.rebirth
 if not integer(state.get("schema"),SCHEMA,SCHEMA) or state.get("rules")!=RULES:return false
 var count:int=int(player.transmigration)
 if state.get("history")=="legacy_unknown":
  return count>0 and exact_keys(state,COMMON)
 if not exact_keys(state,FIELDS):return false
 if state.get("history")=="zero":
  if count!=0 or state.get("last_transaction")!="":return false
  for key in ["equation","round_points","consumed_gm_points"]:
   if not integer(state.get(key),0,0):return false
  for key in ["inherited_base","developer_base_delta"]:
   if not state.get(key) is Dictionary or not state[key].is_empty():return false
  return true
 if state.get("history")!="natural" or count<1 or count>5 or not integer(player.get("level"),1,1000000):return false
 if not integer(state.get("equation"),0,0x7fffffff):return false
 var equation:int=int(state.equation)
 var q:int=(equation>>16)&65535
 var levels:int=equation&65535
 if q>20*count or levels<80*count or levels>130*count:return false
 if not integer(state.get("round_points"),10*count,10*count):return false
 if not integer(state.get("consumed_gm_points"),0,1000000000):return false
 if not state.get("last_transaction") is String or state.last_transaction.is_empty() or state.last_transaction.length()>128:return false
 for key in ["inherited_base","developer_base_delta"]:
  if not state.get(key) is Dictionary or not exact_keys(state[key],STATS):return false
 if not player.get("base_stats") is Dictionary or not player.get("allocated_stats") is Dictionary:return false
 if player.has("legacy_stat_offset") and (not player.legacy_stat_offset is Dictionary or not player.legacy_stat_offset.is_empty()):return false
 var assigned:=0
 for stat in STATS:
  if not integer(state.inherited_base[stat],0,100000000) or not integer(state.developer_base_delta[stat],-100000000,100000000):return false
  if not integer(player.allocated_stats.get(stat),0,100000000) or not integer(player.base_stats.get(stat),0,100000000):return false
  if int(player.base_stats[stat])!=int(state.inherited_base[stat])+100*int(player.allocated_stats[stat])+int(state.developer_base_delta[stat]):return false
  assigned+=int(player.allocated_stats[stat])
 return integer(player.get("stat_points"),0,1000000000) and int(player.stat_points)==point_budget(profile)-assigned

static func exact_keys(value:Dictionary,keys:Array)->bool:
 return value.size()==keys.size() and keys.all(func(key):return value.has(key))

static func point_budget(profile:Dictionary)->int:
 var state:Dictionary=profile.get("rebirth",{})
 var extra:int=int(state.get("round_points",0)) if state.get("history")=="natural" else 0
 return 3*(int(profile.player.level)-1)+int(profile.get("gm_bonus_points",0))+extra

static func record_developer_base(profile:Dictionary)->void:
 var state:Dictionary=profile.get("rebirth",{})
 if state.get("history")!="natural":return
 for stat in STATS:
  state.developer_base_delta[stat]=int(profile.player.base_stats[stat])-int(state.inherited_base[stat])-100*int(profile.player.allocated_stats[stat])

static func continuation_error(profile:Dictionary)->String:
 if not valid(profile) or not profile.has("rebirth"):return "转生历史数据不完整，无法结算。"
 if profile.rebirth.history=="legacy_unknown":return "旧存档转生历史缺失，已保留原属性和资产；不能推算历史后继续转生。"
 if int(profile.player.transmigration)>=5:return "目前仅开放人物一至五转。"
 return ""
