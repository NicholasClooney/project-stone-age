extends RefCounted
## No navigation receipt crosses a timed entrance, maze room or final guard.
const Rules=preload("res://server/original_quests.gd")
const WorldClock=preload("res://server/original_world_clock.gd")
const MapFile=preload("res://scripts/map_file.gd")
static var components:Dictionary={}
static func region(map_id:int,cell:Vector2i)->int:
 if map_id not in [41,42]:return -1
 if not components.has(map_id):
  var map:Dictionary=MapFile.load_map("res://assets/legacy/world/%d.map"%map_id)
  if map.is_empty():return -1
  var labels:Dictionary={};var blocked_npcs:=[Vector2i(33,41),Vector2i(34,41),Vector2i(34,25)]
  var serial:=0
  for y in range(int(map.height)):
   for x in range(int(map.width)):
    var seed:=Vector2i(x,y)
    if labels.has(seed) or seed in blocked_npcs or int(map.blocked[y*int(map.width)+x])!=0:continue
    serial+=1;var queue:Array[Vector2i]=[seed];labels[seed]=serial;var cursor:=0
    while cursor<queue.size():
     var point:Vector2i=queue[cursor];cursor+=1
     for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
      var next:Vector2i=point+delta
      if next.x<0 or next.y<0 or next.x>=int(map.width) or next.y>=int(map.height) or labels.has(next) or next in blocked_npcs:continue
      if int(map.blocked[next.y*int(map.width)+next.x])!=0:continue
      labels[next]=serial;queue.append(next)
  components[map_id]=labels
 return int(components[map_id].get(cell,-1))
static func stage_key(backend)->Array:
 var map_id:int=backend.automation.position_map
 if map_id==400:return ["dream",400,WorldClock.phase_at(WorldClock.hour())]
 if map_id in [41,42]:
  var sage:Dictionary=entry(backend,"seimu/event/event01_2",4,map_id)
  var reward_ready:bool=not sage.is_empty() and backend.quest_arrival.check_action(backend,sage.npc,sage.branch,"ACCEPT").is_empty()
  return ["dream",map_id,region(map_id,backend.automation.position_cell),backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),reward_ready]
 return []
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var map_id:=int(npc.map_id)
 var plain:=npc.duplicate(true);plain.events=[]
 if map_id in [400,6000]:return helper.destination(backend,plain,mode)
 if map_id not in [41,42] or int(backend.automation.position_map)!=map_id:return {}
 var current:Vector2i=backend.automation.position_cell
 if region(map_id,current)<0 or not backend.quest_arrival.has_arrival(backend,map_id,current):return {}
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return {}
 # A project jump, including one within the same room, would revoke the
 # legitimate route. Only offer a stationary talk destination already near.
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(current.x-target.x),absi(current.y-target.y))>2:return {}
 # The original sage at (34,25) has blocked adjacent terrain; its actual
 # talking floor starts two cells south at (34,27). Do not infer a side
 # from the blocked (34,26), and do not accept an arbitrary nearby room.
 var anchors:Array=[target+Vector2i.DOWN,target+Vector2i.UP]
 if str(npc.get("source_script",""))=="seimu/event/event01_2" and target==Vector2i(34,25):anchors=[Vector2i(34,27)]
 if not anchors.any(func(point):return region(map_id,point)>=0 and region(map_id,current)==region(map_id,point)):return {}
 return {"map_id":map_id,"cell":[current.x,current.y],"npc_id":str(npc.id)}

static func entry(backend,script:String,branch_index:int,map_id:int=-1)->Dictionary:
 for npc in backend.quest_catalog.active_npcs_by_source(script):
  if str(npc.get("source_script",""))!=script or map_id>=0 and int(npc.map_id)!=map_id:continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",0))==branch_index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var event:=int(quest.event);var ended:=Rules.flag(profile,"ended",event)
 var previous:bool=Rules.flag(profile,"ended",4) and (event==32 or Rules.flag(profile,"ended",event-1))
 var light:=Rules.item_count(profile,2603)>0
 var map_id:int=backend.automation.position_map
 var cave:int=map_id if map_id in [41,42] else 41
 quest.completion_detail="三轮依次领取空想竖琴、帽子、衣服；只有第三次交先见之光才写END34。保留END4与前轮完成条件。晨门与日夕门通41、夜门通42，使用原1024小时制；须亲自走入当时开放的原门。沿原传送迷宫抵达两只守卫，任选其一挑战原十敌队伍；两图胜后原目标都在41。助手仅在已沿原路合法抵达且当前可对话时保持原地；洞内请沿原路步行，不用项目瞬移绕过路线。捕宠直达为项目便利，不授予领奖资格；现AI未恢复特殊技能，空想帽2605使用头部槽、竖琴2606使用护符槽；空想衣2604尚无可穿戴定义，魔法与抗性未生效。原版行为：≥35级可免费领取先见之光，交仙人后从原20项谢礼随机获得一项，可无限重复；前三轮仍优先完成。先见之光原离线消失尚未实现。"
 helper.add_step(backend,profile,quest,"dream%d:request"%event,entry(backend,"seimu/event/event01_1",34-event),previous and not light and not ended,light or ended,"向村中老人领取本轮先见之光")
 for i in [1,2]:
  helper.add_step(backend,profile,quest,"dream%d:battle:%d"%[event,i],entry(backend,"400/sb_muge%d.arg"%i,0,cave),previous and light and not ended,false,"沿原迷宫抵达守卫，原十敌固定战（二选一）")
 helper.add_step(backend,profile,quest,"dream%d:reward"%event,entry(backend,"seimu/event/event01_2",35-event,cave),previous and light and not ended,ended,"战后交先见之光，领取第%d轮原奖励"%(event-31))
 if map_id in [41,42]:quest.blocked_reason="项目补充：洞内须沿原路步行并赢得终战；助手不能瞬移代走，捕宠传入不能领奖。"
 if not previous:quest.blocked_reason="须先完成成人礼END4及上一轮梦幻任务。"
 elif map_id not in [41,42] and not ended:quest.blocked_reason="亲自走入原时间门：400(97,119)日／夕，邻格晨，400(87,101)夜；助手不直接瞬移入洞。"

 if event==34:
  var repeat_ready:=int(profile.player.level)>=35
  helper.add_step(backend,profile,quest,"dream34:repeat-request",entry(backend,"seimu/event/event01_1",4),repeat_ready and not light,false,"原版行为：免费领取先见之光（可重复，前三轮优先）")
  helper.add_step(backend,profile,quest,"dream34:repeat-reward",entry(backend,"seimu/event/event01_2",4,cave),repeat_ready and light,false,"原版行为：交先见之光，随机20项谢礼之一（可重复）")
  for npc in backend.quest_catalog.active_npcs():
   if str(npc.get("handler",""))!="TimeMan":continue
   var point:String=str(npc.source_script).trim_prefix("genout/tman_400_")
   quest.steps.append({"id":"dream34:time:"+point,"npc_id":str(npc.id),"map_id":400,"cell":npc.cell.duplicate(),"current":false,"done":false,"optional":true,"actionable":true,"label":"查看原入口时间提示（同一服务器时钟） · %s"%point,"source":{"npc_id":str(npc.id),"type":"TimeMan"}})
