extends RefCounted
## Pure job2/event44 proposals. This module never opens or answers a dialogue.
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Rules=preload("res://server/original_quests.gd")
static func supports(job_id:int)->bool:return job_id==2
static func manual(reason:String)->Dictionary:return {"status":"manual","reason":reason}
static func step(value:Dictionary)->Dictionary:return {"status":"step","step":value}
static func floor_base(map_id:int)->int:
 for base in [800,820,840]:
  if map_id>=base and map_id<base+10:return base
 return -1
static func definition(table:Dictionary,source:String,map_id:int)->Dictionary:
 for value in table.get("npcs",[]):
  if value.source_script==source and int(value.map_id)==map_id:return value
 return {}
static func select(b,job_id:int)->Dictionary:
 if not supports(job_id):return manual("仅支持原金布伊任务2。")
 var profile:Dictionary=b.session._profile
 if Rules.flag(profile,"ended",44):return {"status":"done"}
 var table:=Sources.table()
 if table.is_empty():return manual("受审原源表校验失败。")
 if not Sources.integer(profile.player.get("level")):return manual("角色等级无效。")
 var level:=int(profile.player.level)
 var map_id:int=b.automation.position_map
 var origin:Vector2i=b.automation.position_cell
 var base:=floor_base(map_id)
 if base>=0 or map_id in [810,850]:
  if not b.quest_arrival.has_arrival(b,map_id,origin):return manual("保护地图缺少原合法到达，请手动沿原路进入。")
 if map_id in [810,850]:return exchange(b,table,profile,map_id)
 if base>=0:
  # y is a hint only: next_portal independently checks proof and connectivity.
  if origin.y<18:
   for row in table.portals:
    if int(row.from_map)!=map_id:continue
    var portal:Dictionary={"from_map":int(row.from_map),"from_cell":row.from_cell.duplicate(),"to_map":int(row.to_map),"to_cell":row.to_cell.duplicate()}
    if Navigation.new().next_portal(b,portal).is_empty():return manual("受审原楼梯受阻或来源改变，请手动处理。")
    return step({"id":"golden44:stairs:%d"%map_id,"action":"walk_portal","label":"沿原楼梯前往下一层","source":{"policy":"golden44_stairs_v1"},"portal":portal})
   return manual("此楼层没有受审原楼梯。")
  var offset:=map_id-base
  var fist:=offset in [2,4,7]
  if not fist and not 2752 in profile.original_items:return manual("缺少猜谜的参加票2752，请手动取得后继续。")
  var source:="genout/%s_%d_%d_19"%["jan" if fist else "quz",map_id,29 if offset%2==0 else 18]
  return service(b,table,source,map_id,"challenge")
 if Rules.flag(profile,"now",44):return manual("已领取会员证；请沿合法原路回到领奖房，不自动取消或重领。")
 if level<30:return manual("原道场入场需要30级。")
 var ticket:=2757 if level>=70 else (2756 if level>=50 else 2755)
 if not ticket in profile.original_items:return manual("缺少原入场券，请手动购买；自动任务不代购。")
 # Choose only the player's current original lobby; no invented entrance warp.
 if not map_id in [811,831,851]:return manual("请先沿原路到对应道场受理入口。")
 if (level>=70)!=(map_id==851):return manual("当前道场不匹配原等级入场档。")
 var x:=29 if map_id==851 else (28 if level>=50 else 30)
 return service(b,table,"genout/wpm_%d_%d_20"%[map_id,x],map_id,"entry")
static func service(b,table:Dictionary,source:String,map_id:int,phase:String)->Dictionary:
 var expected:=definition(table,source,map_id)
 if expected.is_empty():return manual("未受审的原服务来源。")
 var npc:=Sources.npc(b,expected)
 if npc.is_empty():return manual("原服务NPC身份、位置或完整定义已改变。")
 if not b.quest_arrival.check_action(b,npc,{},"SERVICE").is_empty():return manual("原服务缺少合法到达资格。")
 if not reachable(b,npc):return manual("原服务NPC当前不可达。")
 return step({"id":"golden44:%s:%s"%[phase,source],"action":"source_service","label":"原问答、猜拳或持票入场","npc_id":str(npc.id),"map_id":map_id,"cell":npc.cell.duplicate(),"source":{"policy":"golden44_service_v1","source_id":source,"service_id":str(npc.service_id),"kind":str(npc.kind)}})
static func exchange(b,table:Dictionary,profile:Dictionary,room:int)->Dictionary:
 var started:=Rules.flag(profile,"now",44)
 if started and not 2753 in profile.original_items:return manual("会员证已领取但未持有；不会自动取消或重领。")
 if not started and Rules.Session.bag_slots(profile)+1>15:return manual("道具栏已满，请先留出会员证位置。")
 if started and profile.pets.size()>=Rules.Session.PET_CAPACITY:return manual("随身宠物栏已满，请先空出位置。")
 if started and not Sources.same(b.quest_catalog.reward_pets.get("14",{}),table.reward_pet):return manual("原14号金布伊奖励定义已改变。")
 var source:="quiz/equiz_02" if started else "quiz/equiz_01"
 var expected:=definition(table,source,room)
 var npc:=Sources.npc(b,expected) if not expected.is_empty() else {}
 if npc.is_empty():return manual("原会员证或金布伊兑换NPC定义已改变。")
 var branch:Dictionary=b.original_quests.branch_for(npc,profile)
 var index:=4 if started else 3
 if npc.branches.size()!=1 or not Sources.same(branch,npc.branches[0]) or not Sources.same(branch.get("source_branch_index"),index):return manual("当前原分支不匹配受审兑换。")
 if not b.quest_arrival.check_action(b,npc,branch,str(branch.type)).is_empty():return manual("原兑换缺少合法到达资格。")
 if not reachable(b,npc):return manual("原兑换NPC当前不可达。")
 return step({"id":"golden44:%s:%d"%["exchange" if started else "claim",room],"action":"source_exchange","label":"原会员证兑换金布伊" if started else "领取原会员证","npc_id":str(npc.id),"map_id":room,"cell":npc.cell.duplicate(),"source":{"policy":"golden44_pet14_v1" if started else "golden44_claim_v1","source_id":source,"branch_index":index,"branch_data":branch.duplicate(true)}})
static func reachable(b,npc:Dictionary)->bool:
 var nav:=Navigation.new()
 var map_id:int=b.automation.position_map
 if map_id!=int(npc.map_id):return false
 var origin:Vector2i=b.automation.position_cell
 var anchor:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 var occupied:=nav._portal_occupied(b,map_id)
 if not nav.floor_cell(b,map_id,origin,{}):return false
 var delta:=origin-anchor
 if maxi(absi(delta.x),absi(delta.y))<=2:return true
 for dy in range(-2,3):
  for dx in range(-2,3):
   var goal:=anchor+Vector2i(dx,dy)
   if b.quest_helper.places.links(map_id).has(goal) or not nav.floor_cell(b,map_id,goal,occupied):continue
   if not nav.local_path(b,map_id,origin,goal,occupied).is_empty():return true
 return false
