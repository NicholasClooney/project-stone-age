extends RefCounted
## Coordinator-confirmed scope: existing job22, NOW18 allowed, stop at axe+END19.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="jaruga/event/20501ev1",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=22:return hold("unsupported_job","哈恩限job22内部阶段；job19属于五兄弟。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",19):
  if 2465 in held:return {"status":"done"}
  return hold("missing_axe","已END19但未持斧头；不得CLEAN19重领或进入额外循环。")
 if 2465 in held:return hold("inconsistent_axe","持斧而未END19，等待核对；不交斧开启END18后续。")
 if not 2466 in held:
  if Rules.flag(p,"ended",18) or 2467 in held:return hold("commission_unavailable","原委托源已被后续分支遮蔽；不清旗、不采木。")
  if Rules.flag(p,"now",18):return hold("replace_commission","允许原NOW18补委托；精确MESSAGE合同待核。","jaruga/event/20501ev3",42)
  if int(p.player.level)<=14:return hold("level","原委托LV>14。")
  return hold("commission","允许原REQUEST开始NOW18；仅前置委托，不继续END18交斧。","jaruga/event/20501ev3",50)
 if not Rules.flag(p,"now",19):return hold("request_axe","待持2466原REQUEST，禁止购买额外壶。","jaruga/event/20501ev1",40)
 if 2464 in held:return hold("claim_axe","待原ACCEPT交水/委托并消费壶；取得2465且END19后停止。","jaruga/event/20501ev1",15)
 if 2463 in held:return hold("fill_water","待水管理员原ACCEPT及保护路线。","jaruga/event/20501ev2",15)
 return hold("replace_pot","待原MESSAGE补壶合同；不代买壶。","jaruga/event/20501ev1",26)

# First execution slice, deliberately separate from select() until core freezes
# admission/registry routing. Exact ordinary delivery shape; no new service action.
const SOURCE_PATH="res://server/quest_auto_harn_sources.json"
const SOURCE_SHA="88d81bfdabe97f0a0a9561d39dd9376729dc860f73fc0a0c0e4502754024dc12"
static func source_table()->Dictionary:
 if not FileAccess.file_exists(SOURCE_PATH):return {}
 var raw:=FileAccess.get_file_as_string(SOURCE_PATH)
 if raw.sha256_text()!=SOURCE_SHA:return {}
 var parsed:Variant=JSON.parse_string(raw)
 return parsed if parsed is Dictionary else {}
static func same_source(a:Variant,b:Variant)->bool:
 if a is bool or b is bool:return a is bool and b is bool and a==b
 if a is int or a is float:
  return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and float(a)==floor(float(a)) and float(b)==floor(float(b)) and a==b
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key in a:
   if not b.has(key) or not same_source(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for index in range(a.size()):
   if not same_source(a[index],b[index]):return false
  return true
 return typeof(a)==typeof(b) and a==b
static func commission_proposal(b)->Dictionary:
 var current:=select(b,22)
 if current.get("stage","")!="commission":return current
 return _recipe_proposal(b,"commission")

## Unregistered exact ordinary actions. Refills remain manual until separately reviewed.
static func axe_proposal(b)->Dictionary:
 var current:=select(b,22)
 if current.get("status")=="done":return current
 var stage:=str(current.get("stage",""))
 if stage not in ["commission","request_axe","fill_water","claim_axe"]:return current
 return _recipe_proposal(b,stage)

## Ordinary NPC projection only; raw identity must already have passed in full.
## Preserve fixed source placement and every field except activation filtering.
static func expected_active(expected:Dictionary,enabled_events:Array)->Dictionary:
 var projected:Dictionary=expected.duplicate(true)
 projected.branches=[]
 for branch in expected.get("branches",[]):
  if branch.get("enabled",false) and branch.get("events",[]).any(func(event):return int(event) in enabled_events):
   projected.branches.append(branch.duplicate(true))
 return projected

static func matches_active(expected:Dictionary,active:Dictionary,enabled_events:Array)->bool:
 return same_source(active,expected_active(expected,enabled_events))

static func _recipe_proposal(b,key:String)->Dictionary:
 var table:=source_table()
 if table.is_empty():return hold("source_changed","哈恩完整锁源描述缺失或改变。")
 # Lock all original branches, including forbidden branches and their order.
 # Array index is a locator only after full identity equality, never authority.
 for expected in table.npcs:
  var matches_count:=0
  for actual in b.quest_catalog.npcs:
   if actual.get("id")==expected.id:
    matches_count+=1
    if not same_source(actual,expected):return hold("source_changed","哈恩完整原NPC/分支顺序已改变。")
  if matches_count!=1:return hold("source_changed","哈恩原NPC源身份不唯一。")
 var profile:Dictionary=b.session.snapshot()
 if not b.quest_catalog.jobs.any(func(job):return job.get("id")==22 and job.get("event")==18):
  return hold("source_changed","原job22/event18映射已改变。")
 if not 18 in b.quest_catalog.enabled_events or not 19 in b.quest_catalog.enabled_events:
  return hold("source_changed","原18/19事件未开放。")
 var recipe:Dictionary=table.recipes[key]
 var expected:Dictionary={}
 for candidate in table.npcs:
  if candidate.id==recipe.npc_id:expected=candidate
 # Read-only projection; don't call npc_by_id(), which refreshes spawn state.
 var npc:Dictionary=b.quest_catalog.active_npc(recipe.npc_id)
 if not matches_active(expected,npc,b.quest_catalog.enabled_events):return hold("source_changed","当前人物位置/分支投影与原源不符。")
 var branch:Dictionary=b.original_quests.branch_for(npc,profile)
 var locked:Dictionary=expected.branches[int(recipe.branch_index)]
 if not same_source(branch,locked):return hold("source_changed","当前先匹配分支不是受审制斧步骤。")
 if str(branch.type) not in ["REQUEST","ACCEPT"]:return hold("unsupported_action","补件MESSAGE须独立审核。")
 if str(branch.type)=="REQUEST" and Rules.flag(profile,"now",int(branch.event)):
  return hold("cancel_forbidden","不确认原REQUEST取消流程。")
 var worn:=Rules.worn_item_hint(profile,str(branch.condition))
 if not worn.is_empty():return hold("worn_item",worn)
 var received:int=Rules.item_list(str(branch.actions.get("GetItem",""))).size()
 # Original REQUEST checks before deletion; ACCEPT checks net capacity.
 if str(branch.type)=="REQUEST" and Rules.Session.bag_slots(profile)+received>15:
  return hold("bag_full","原REQUEST道具栏空间不足。")
 var capacity:=profile.duplicate(true)
 Rules.remove_items(capacity,str(branch.actions.get("DelItem","")))
 if Rules.Session.bag_slots(capacity)+received>15:return hold("bag_full","原交易净道具空间不足。")
 if not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):
  return hold("arrival_required","当前保护位置缺少原合法到达，不以提案恢复proof。")
 return {"status":"step","step":{"id":"harn:"+key,"npc_id":str(npc.id),
  "map_id":int(npc.map_id),"cell":npc.cell.duplicate(),"current":true,"done":false,"actionable":true,
  "label":"沿原路完成制斧步骤："+key,"auto_choices":["yes","ok"],
  "source":{"npc_id":str(npc.id),"branch":int(recipe.branch_index),"type":str(branch.type),
   "condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_data":branch.duplicate(true),
   "audit_policy":"harn_"+key+"_v1","source_line":int(recipe.source_line),
   "source_sha":str(table.sources[recipe.npc_id].sha256)}}}

## Exact audited original portal only; never establishes arrival or chooses a route.
static func reviewed_portal(b,point:Dictionary)->bool:
 if not point.get("portal") is Dictionary:return false
 var link:Dictionary=point.portal
 var from_map:int=b.automation.position_map
 var to_map:int=point.get("map_id",-1)
 var wood_from:=from_map>=20501 and from_map<=20508
 var wood_to:=to_map>=20501 and to_map<=20508
 if not ((wood_from and wood_to) or (from_map==200 and to_map==20501) or (from_map==20501 and to_map==200) or (from_map==20508 and to_map==200) or [from_map,to_map] in [[3300,200],[200,3300]]):return false
 if bool(link.get("disabled",false)) or link.has("gate_source"):return false
 var table:=source_table()
 if table.is_empty():return false
 for original in table.portals:
  if same_source(link,original) and same_source(point.cell,original.target):
   return from_map==int(original.from_map) and to_map==int(original.to_map) and b.automation.position_cell==Vector2i(int(original.cell[0]),int(original.cell[1]))
 return false
