extends RefCounted
## Dormant 2b policy. Does not register job2, execute a service or grant proof.
const Motion=preload("res://server/quest_auto_motion.gd")
const Rules=preload("res://server/original_quests.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const SERVICE_TABLE="res://assets/legacy/server/golden-bui.json"
const SERVICE_TABLE_SHA="03aa97fd30d4be155e83e0e3972f8cd9c745dfa5d7424547e23e69f059bfe403"
const CLAIM_BRANCH={"event":44,"type":"REQUEST","condition":"LV>0","texts":{"RequestMsg":"\n\n厉害！没想到能够来到12楼呀！\n给来到这里的你猜谜大师的\n入门证吧！可以收下吗？","ThanksMsg":"\n\n把这个入门证交给隔壁的伊那多\n询问成为猜谜大师的课题吧！\n你也以猜谜大师为目标！","StopMsg":"\n\n\n不想成为猜谜大师？","EndStopMsg":"\n\n\n那么，等你想来的时候再来吧！","NoStopMsg":"\n\n\n这样的话，快点把入门证交给伊那多喔！","ItemFullMsg":"\n\n\n道具已经满了无法收下的样子喔。"},"actions":{"GetItem":"2753"},"source_branch_index":3,"source_line":29,"enabled":true,"events":[44],"source":"quiz/equiz_01"}
const PET_BRANCH={"event":44,"type":"ACCEPT","condition":"NOWEV=44&ITEM=2753","texts":{"AcceptMsg":"\n\n哎呀！那个是猜谜大师的入门证吧！\n你也迈向猜谜大师之路了吗？","ThanksMsg":"\n很好，很有干劲喔！\n那么的话我就出成为猜谜大师的课题啰\n等到现在交给你的稀有宠物\n等级成为LV77之后是否可以带来给我呢？\n如果无法达成这个条件的话我就没有办法带你到成为\n猜谜大师的认定场\n认定场喔。那么、加油啰！","PetFullMsg":"\n\n因为宠物太多而无法交给你喔。\n能否把宠物的数量减少之后再来呢？"},"actions":{"GetPet":"14","DelItem":"2753","EndSetFlg":"44"},"source_branch_index":4,"source_line":38,"enabled":true,"events":[44],"source":"quiz/equiz_02"}
const PET14={"enemy_id":14,"template_id":12,"species":"original_12","level":1,"name":"金布伊","initial":25,"wild_growth":4.5,"weights":[31,20,32,12],"modai":270,"variable_ai":0,"elements":[0,0,30,70],"skill_slots":10,"sprite":100255,"size":0,"source":"gmsv/data/enemy.txt","source_line":10,"base_source":"gmsv/data/enemybase.txt","base_source_line":12}
const GATES={
 "genout/wpm_811_30_20":[811,[30,20],800,2755,30,49],
 "genout/wpm_831_30_20":[831,[30,20],800,2755,30,49],
 "genout/wpm_811_28_20":[811,[28,20],820,2756,50,69],
 "genout/wpm_831_28_20":[831,[28,20],820,2756,50,69],
 "genout/wpm_851_29_20":[851,[29,20],840,2757,70,2147483647]
}
static func denied(reason:String)->Dictionary:
 return {"ok":false,"reason":reason}
static func exact_keys(value:Dictionary,keys:Array)->bool:
 if value.size()!=keys.size():return false
 for key in keys:
  if not value.has(key):return false
 return true
## JSON numbers may arrive as floats. Normalize mathematical values only;
## booleans never match numeric source fields, and no fractional truncation.
static func same_source(actual:Variant,expected:Variant)->bool:
 if expected is int or expected is float:
  return (actual is int or actual is float) and is_finite(float(actual)) and actual==expected
 if expected is Array:
  if not actual is Array or actual.size()!=expected.size():return false
  for index in range(expected.size()):
   if not same_source(actual[index],expected[index]):return false
  return true
 if expected is Dictionary:
  if not actual is Dictionary or actual.size()!=expected.size():return false
  for key in expected:
   if not actual.has(key) or not same_source(actual[key],expected[key]):return false
  return true
 return typeof(actual)==typeof(expected) and actual==expected
static func recipe(source_id:String)->Dictionary:
 if GATES.has(source_id):
  var gate:Array=GATES[source_id]
  return {"map_id":gate[0],"cell":gate[1].duplicate(),"kind":"golden_bui_gate"}
 for base in [800,820,840]:
  for offset in [0,1,2,3,4,5,6,7,8,9]:
   var fist:bool=offset in [2,4,7]
   var x:int=29 if offset%2==0 else 18
   if source_id=="genout/%s_%d_%d_19"%["jan" if fist else "quz",base+offset,x]:
    return {"map_id":base+offset,"cell":[x,19],"kind":"golden_bui_janken" if fist else "golden_bui_quiz"}
 return {}
static func job_enabled(b,job_id:int)->bool:
 if job_id!=2 or not 44 in b.quest_catalog.enabled_events:return false
 var jobs:Array=b.quest_catalog.jobs.filter(func(job):return Motion.same_integer(job.get("id"),2))
 return jobs.size()==1 and Motion.same_integer(jobs[0].get("event"),44)
static func validate_step(b,job_id:int,step:Dictionary)->Dictionary:
 if not job_enabled(b,job_id):return denied("未审核的原任务入口。")
 if not step.get("id") is String or step.id.is_empty() or not step.get("label") is String:return denied("原步骤标识不完整。")
 if not step.get("source") is Dictionary:return denied("原步骤来源不完整。")
 if step.get("action")=="walk_portal":return validate_portal(b,step)
 if not exact_keys(step,["id","action","label","npc_id","map_id","cell","source"]):return denied("原步骤含有未审核字段。")
 var source:Dictionary=step.source
 if not source.get("source_id") is String:return denied("原人物来源不完整。")
 var expected:Dictionary={}
 var branch:Dictionary={}
 if step.action=="source_service":
  if not exact_keys(source,["policy","source_id","service_id","kind"]) or source.get("policy")!="golden44_service_v1":return denied("原服务策略未审核。")
  expected=recipe(source.source_id)
  if expected.is_empty() or source.service_id!=source.source_id or source.kind!=expected.kind:return denied("原服务来源未审核。")
  # Only verifies static serialized source bytes; never parses private service
  # answers, pending.service_state, service catalog or the opponent RNG.
  if not FileAccess.file_exists(SERVICE_TABLE) or FileAccess.get_file_as_string(SERVICE_TABLE).sha256_text()!=SERVICE_TABLE_SHA:return denied("原服务源表已变化。")
 elif step.action=="source_exchange":
  if not exact_keys(source,["policy","source_id","branch_index","branch_data"]):return denied("原兑换来源不完整。")
  var claim:bool=source.get("policy")=="golden44_claim_v1"
  if not claim and source.get("policy")!="golden44_pet14_v1":return denied("原兑换策略未审核。")
  if source.source_id!=("quiz/equiz_01" if claim else "quiz/equiz_02"):return denied("原兑换人物未审核。")
  branch=CLAIM_BRANCH if claim else PET_BRANCH
  # The imported array contains ONLY event44: source indexes 3/4 are metadata,
  # never indexes into the projected branches array (whose index is zero).
  if not Motion.same_integer(source.get("branch_index"),branch.source_branch_index) or not same_source(source.get("branch_data"),branch):return denied("完整原分支不匹配。")
  var room=Motion.integer(step.get("map_id"))
  if not room in [810,850]:return denied("原兑换房间未审核。")
  expected={"map_id":room,"cell":[29 if claim else 28,16]}
  if not claim and not same_source(b.quest_catalog.reward_pets.get("14",{}),PET14):return denied("原GetPet14定义已经变化。")
 else:return denied("原动作未审核。")
 if not Motion.same_integer(step.get("map_id"),expected.map_id) or Motion.cell(step.get("cell"))!=expected.cell:return denied("原人物位置不匹配。")
 var step_id:String="golden44:%s:%s"%["entry" if expected.get("kind")=="golden_bui_gate" else "challenge",source.source_id]
 if step.action=="source_exchange":step_id="golden44:%s:%d"%["claim" if source.policy=="golden44_claim_v1" else "exchange",expected.map_id]
 if step.id!=step_id:return denied("原逻辑步骤身份不匹配。")
 var npc_id:String="%s@%d:%d:%d"%[source.source_id,expected.map_id,expected.cell[0],expected.cell[1]]
 if step.get("npc_id")!=npc_id:return denied("原人物身份不匹配。")
 var pinned:Dictionary={}
 for candidate in Sources.table().get("npcs",[]):
  if candidate.id==npc_id:pinned=candidate;break
 if pinned.is_empty():return denied("原人物锁源表不可用。")
 # Full immutable identity via the read-only 4b projection. Never refresh
 # NPC state as a side effect of validating a proposed action.
 var npc:Dictionary=Sources.npc(b,pinned)
 if npc.is_empty():return denied("原人物必须唯一且完整定义匹配。")
 if step.action=="source_service":
  if npc.get("kind")!=expected.kind or npc.get("service_id")!=source.service_id or npc.get("branches")!=[]:return denied("原服务定义已经变化。")
 else:
  if npc.has("kind") or not same_source(npc.get("branches"),[branch]):return denied("原兑换分支已经变化。")
 return {"ok":true,"npc":npc.duplicate(true)}

static func validate_portal(b,step:Dictionary)->Dictionary:
 if not exact_keys(step,["id","action","label","source","portal"]) or step.source!={"policy":"golden44_stairs_v1"} or not step.portal is Dictionary:return denied("原楼梯提案不完整。")
 var row:Dictionary=Sources.portal_row(step.portal)
 if row.is_empty() or step.id!="golden44:stairs:%d"%int(row.from_map):return denied("原楼梯不在已审核的30条表内。")
 var links:Dictionary=b.quest_helper.places.links(int(row.from_map))
 var link:Dictionary=links.get(Vector2i(int(row.from_cell[0]),int(row.from_cell[1])),{})
 if link.has("gate_source") or link.get("disabled",false) or not Sources.same(link,row.live_link):return denied("完整原楼梯link已经改变。")
 var count:=0
 for value in links.values():
  if Sources.same(value,row.live_link):count+=1
 if count!=1:return denied("原楼梯link必须唯一。")
 return {"ok":true,"portal":step.portal.duplicate(true)}

## Admission is separate from an in-flight paid page: never require another
## quiz ticket after the original confirm transaction has already paid it.
static func validate_open(b,job_id:int,step:Dictionary)->Dictionary:
 var checked:=validate_step(b,job_id,step)
 if not checked.ok:return checked
 var profile:Dictionary=b.session.snapshot()
 if Rules.flag(profile,"ended",44):return denied("原任务已经完成。")
 var level:int=int(profile.player.level)
 if level<30:return denied("原道场至少需要角色30级。")
 if b.battle_open or not b.session._pending.is_empty() or not b.original_quests.pending.is_empty():return denied("当前战斗或对话尚未结束。")
 if b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return denied("请先退出团队。")
 if step.action=="walk_portal":
  if Navigation.new().next_portal(b,step.portal).is_empty():return denied("原楼梯缺少合法连续到达或已受阻。")
  return checked
 var npc:Dictionary=checked.npc
 var origin:Vector2i=b.automation.position_cell
 var target:Vector2i=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if b.automation.position_map!=int(npc.map_id) or maxi(absi(origin.x-target.x),absi(origin.y-target.y))>2:return denied("原人物不在合法近距内。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,origin) or not b.original_quests.allowed(b,npc):return denied("原路到达资格已经失效。")
 if step.action=="source_service":
  if npc.kind=="golden_bui_gate":
   var gate:Array=GATES[step.source.source_id]
   if level<gate[4] or level>gate[5] or not gate[3] in profile.original_items:return denied("缺少原等级或门票，请玩家到原柜台办理。")
  elif npc.kind=="golden_bui_quiz" and not 2752 in profile.original_items:return denied("缺少猜谜参加票，请手动取得后继续。")
 else:
  var branch:Dictionary=step.source.branch_data
  if not same_source(b.original_quests.branch_for(npc,profile),branch):return denied("原兑换条件已经变化。")
  if step.source.policy=="golden44_claim_v1":
   if Rules.flag(profile,"now",44) or 2753 in profile.original_items:return denied("会员证已领取或已丢失，请手动核对。")
   if Rules.Session.bag_slots(profile)>=15:return denied("道具栏已满。")
  elif not Rules.flag(profile,"now",44) or not 2753 in profile.original_items or profile.pets.size()>=Rules.Session.PET_CAPACITY:return denied("会员证或宠物栏条件不满足。")
 return checked

## Exact possible original transaction results, not a generic SERVICE grant.
## These are public source action boundaries, independent of private questions
## and opponent RNG. The original service still decides which result occurred.
static func transaction(step:Dictionary,branch:Dictionary,phase:String)->bool:
 if step.get("action")=="source_exchange":
  return same_source(branch,step.source.branch_data) and phase==("REQUEST" if step.source.policy=="golden44_claim_v1" else "reward")
 if step.get("action")!="source_service" or phase!="SERVICE" or not exact_keys(branch,["event","actions","texts"]) or branch.event!=-1 or branch.texts!={}:return false
 var source:String=step.source.source_id
 var actions:Dictionary=branch.actions
 if GATES.has(source):
  var gate:Array=GATES[source]
  return actions=={"DelItem":"%d*1"%gate[3],"Warp":"%d,14,26"%gate[2]}
 var rule:=recipe(source)
 if rule.is_empty():return false
 var map_id:int=int(rule.map_id)
 var offset:int=map_id%20
 var base:int=map_id-offset
 var win:String="%d,%d,15"%[map_id,int(rule.cell[0])]
 if rule.kind=="golden_bui_janken":
  var lose:String="%d,%d,%d"%[map_id-1,20 if offset==7 else 27,22 if offset==7 else 21]
  return actions=={"DelItem":"2751*1"} or actions=={"Warp":win} or actions=={"Warp":lose}
 if actions=={"DelItem":"2752*1"}:return true
 if offset==0:return actions=={"GetItem":"2754","Warp":win}
 if actions=={"Warp":win}:return true
 var failures:Dictionary={3:[2,20,22],5:[4,20,22],6:[5,27,21],8:[6,20,22],9:[1,27,21]}
 if not failures.has(offset):return false
 var point:Array=failures[offset]
 return actions=={"Warp":"%d,%d,%d"%[base+int(point[0]),point[1],point[2]]}
