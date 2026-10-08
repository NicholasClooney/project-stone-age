extends RefCounted
## Pure persistent candidates. No clock, file, inventory, RNG or battle writes.
const STEP="jewels:hunt:2760"
const MAX_COUNTER=2147483647
const MAX_MSEC=9007199254740991
const ENTRY_KEYS=["budget_id","origin_run_id","generation","revision","limit_ms","used_ms","existing_items","saved_battles","new_items","issued_seq","settled_seq","open_span","recovery_blocked"]
static func empty()->Dictionary:
 return {"version":1,"recovery_blocked":false,"entries":{}}
static func integer(value:Variant,low:int=0,high:int=MAX_COUNTER)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=low and value<=high
static func exact(value:Dictionary,keys:Array)->bool:
 return value.size()==keys.size() and keys.all(func(key):return value.has(key))
static func opaque(value:Variant)->bool:
 return value is String and value.length()==32 and value.is_valid_hex_number()
static func valid_entry(value:Variant)->bool:
 if not value is Dictionary or not exact(value,ENTRY_KEYS):return false
 if not opaque(value.budget_id) or not opaque(value.origin_run_id):return false
 for key in ["generation","revision","existing_items","saved_battles","new_items","issued_seq","settled_seq"]:
  if not integer(value[key]):return false
 if not integer(value.limit_ms,60000,10800000) or not integer(value.used_ms,0,MAX_MSEC):return false
 if not value.open_span is bool or not value.recovery_blocked is bool:return false
 if value.settled_seq>value.issued_seq or value.issued_seq-value.settled_seq>1:return false
 return value.issued_seq>value.settled_seq if value.open_span else value.issued_seq==value.settled_seq
static func valid(value:Variant)->bool:
 if not value is Dictionary or not exact(value,["version","recovery_blocked","entries"]):return false
 if not integer(value.version,1,1) or not value.recovery_blocked is bool or not value.entries is Dictionary:return false
 for key in value.entries:
  if key!=STEP or not valid_entry(value.entries[key]):return false
 return true
static func valid_profile(profile:Dictionary)->bool:
 if profile.has("quest_loot"):return valid(profile.quest_loot)
 return integer(profile.get("version"),1,7)
static func recovered(profile:Dictionary,from_backup:bool)->Dictionary:
 # Approved cold retirement: retain the selected source's saved lower bound.
 # No reset, no new budget/generation, no invented elapsed time or rewards.
 if not valid_profile(profile):return {}
 var ledger:Dictionary=profile.get("quest_loot",empty()).duplicate(true)
 if ledger.entries.is_empty():
  # A backup without an entry cannot prove that no budget ever existed.
  if from_backup:ledger.recovery_blocked=true
  return ledger
 for key in ledger.entries:
  var entry:Dictionary=ledger.entries[key]
  if from_backup or ledger.recovery_blocked or entry.recovery_blocked or entry.open_span:
   entry.open_span=false
   entry.settled_seq=entry.issued_seq
   if entry.revision<MAX_COUNTER:entry.revision+=1
   # At counter exhaustion the existing open gate still denies a new span.
   entry.recovery_blocked=false
 ledger.recovery_blocked=false
 return ledger
static func resume_is_loot(value:Variant)->bool:
 if not value is Dictionary:return false
 var identity_value:Variant=value.get("identity")
 if identity_value is Dictionary:
  var step_value:Variant=identity_value.get("step_id")
  if step_value is String and step_value==STEP:return true
 var phase_value:Variant=value.get("phase")
 var quest_value:Variant=value.get("quest_id")
 return phase_value is String and phase_value in ["loot_admission","loot_battle"] and integer(quest_value,-1,-1)
static func denied(reason:String)->Dictionary:return {"ok":false,"reason":reason}
static func result(ledger:Dictionary)->Dictionary:return {"ok":true,"ledger":ledger}
static func identity(entry:Dictionary)->Dictionary:
 return {"budget_id":entry.budget_id,"generation":entry.generation,"revision":entry.revision}
static func matches(entry:Dictionary,expected:Dictionary)->bool:
 return exact(expected,["budget_id","generation","revision"]) and expected==identity(entry)
static func acquire(ledger:Dictionary,key:String,budget_id:String,run_id:String,minutes:Variant,existing:Variant)->Dictionary:
 if not valid(ledger) or key!=STEP:return denied("刷物预算资料无效。")
 if ledger.recovery_blocked:return denied("备份预算不确定，需明确确认重置。")
 if ledger.entries.has(key):
  if ledger.entries[key].recovery_blocked:return denied("活跃时段无法核实，需明确重置该预算。")
  return result(ledger.duplicate(true)) # New run never replaces old limit/counters.
 if not opaque(budget_id) or not opaque(run_id) or not integer(minutes,1,180) or not integer(existing):return denied("新预算参数无效。")
 var candidate:=ledger.duplicate(true)
 candidate.entries[key]={"budget_id":budget_id,"origin_run_id":run_id,"generation":0,"revision":0,"limit_ms":int(minutes)*60000,"used_ms":0,"existing_items":int(existing),"saved_battles":0,"new_items":0,"issued_seq":0,"settled_seq":0,"open_span":false,"recovery_blocked":false}
 return result(candidate)
static func editable(ledger:Dictionary,key:String,expected:Dictionary)->bool:
 return valid(ledger) and ledger.entries.has(key) and matches(ledger.entries[key],expected) and ledger.entries[key].revision<MAX_COUNTER
static func open(ledger:Dictionary,key:String,expected:Dictionary)->Dictionary:
 if not editable(ledger,key,expected):return denied("预算身份已过期。")
 var entry:Dictionary=ledger.entries[key]
 if ledger.recovery_blocked or entry.recovery_blocked or entry.open_span:return denied("预算未安全关闭或恢复不确定。")
 if entry.used_ms>=entry.limit_ms or entry.issued_seq>=MAX_COUNTER:return denied("本步刷物预算已到限。")
 var candidate:=ledger.duplicate(true)
 candidate.entries[key].issued_seq+=1
 candidate.entries[key].revision+=1
 candidate.entries[key].open_span=true
 return result(candidate)
static func progress(ledger:Dictionary,key:String,expected:Dictionary,total_used:Variant,close:bool=false)->Dictionary:
 if not editable(ledger,key,expected):return denied("预算身份已过期。")
 var entry:Dictionary=ledger.entries[key]
 if ledger.recovery_blocked or entry.recovery_blocked or not entry.open_span or not integer(total_used,entry.used_ms,MAX_MSEC):return denied("活跃预算累计无效。")
 var candidate:=ledger.duplicate(true)
 var next:Dictionary=candidate.entries[key]
 next.used_ms=int(total_used);next.revision+=1
 if close:next.open_span=false;next.settled_seq=next.issued_seq
 return result(candidate)
static func settle(ledger:Dictionary,key:String,receipt:Dictionary,battle_id:String,total_used:Variant,received:Variant)->Dictionary:
 if not valid(ledger) or not ledger.entries.has(key):return denied("预算资料无效。")
 var entry:Dictionary=ledger.entries[key]
 if not exact(receipt,["budget_id","generation","issued_seq","battle_id"]) or not integer(receipt.generation) or not integer(receipt.issued_seq,1) or receipt.battle_id!=battle_id or battle_id.is_empty():return denied("原战斗预算凭据无效。")
 if receipt.budget_id!=entry.budget_id or receipt.generation!=entry.generation or receipt.issued_seq!=entry.issued_seq or receipt.issued_seq<=entry.settled_seq:return denied("预算结算重复或过期。")
 if not integer(received,0,MAX_COUNTER-entry.new_items) or entry.saved_battles>=MAX_COUNTER:return denied("预算计数已到安全上限。")
 var settled:=progress(ledger,key,identity(entry),total_used,true)
 if not settled.ok:return settled
 settled.ledger.entries[key].saved_battles+=1
 settled.ledger.entries[key].new_items+=int(received)
 return settled # Caller saves original battle outcome AND ledger atomically.
static func adjust(ledger:Dictionary,key:String,expected:Dictionary,minutes:Variant)->Dictionary:
 if not editable(ledger,key,expected) or not integer(minutes,1,180):return denied("预算调整身份或额度无效。")
 var entry:Dictionary=ledger.entries[key]
 if ledger.recovery_blocked or entry.recovery_blocked or entry.open_span:return denied("请在本步战斗结算并暂停后调整预算。")
 var candidate:=ledger.duplicate(true)
 candidate.entries[key].limit_ms=int(minutes)*60000;candidate.entries[key].revision+=1
 return result(candidate)
static func reset(ledger:Dictionary,key:String,expected:Dictionary,minutes:Variant,acknowledge_recovery:bool=false)->Dictionary:
 if not editable(ledger,key,expected) or not integer(minutes,1,180):return denied("重置预算身份或额度无效。")
 var entry:Dictionary=ledger.entries[key]
 if entry.generation>=MAX_COUNTER:return denied("预算代数已到安全上限。")
 if (ledger.recovery_blocked or entry.recovery_blocked) and not acknowledge_recovery:return denied("请明确确认中断时段与备份预算不确定。")
 if entry.open_span and not entry.recovery_blocked:return denied("活跃时段尚未安全关闭。")
 var candidate:=ledger.duplicate(true)
 # Explicit recovery confirmation also acknowledges missing backup history.
 # Other entries keep their own recovery locks; never silently unlock them.
 if acknowledge_recovery:candidate.recovery_blocked=false
 var next:Dictionary=candidate.entries[key]
 next.generation+=1;next.revision+=1;next.used_ms=0;next.limit_ms=int(minutes)*60000
 next.open_span=false;next.settled_seq=next.issued_seq;next.recovery_blocked=false
 return result(candidate)
static func reset_missing(ledger:Dictionary,expected_ledger:Dictionary,key:String,budget_id:String,run_id:String,minutes:Variant,existing:Variant,acknowledge_recovery:bool)->Dictionary:
 # A recovered old backup may have lost the entry entirely. Only an explicit
 # reset confirming that uncertainty can create it; ordinary acquire cannot.
 if not valid(ledger) or ledger!=expected_ledger or not ledger.recovery_blocked or ledger.entries.has(key) or not acknowledge_recovery:return denied("缺失预算恢复必须明确确认当前不确定状态。")
 var candidate:=ledger.duplicate(true)
 candidate.recovery_blocked=false
 return acquire(candidate,key,budget_id,run_id,minutes,existing)
