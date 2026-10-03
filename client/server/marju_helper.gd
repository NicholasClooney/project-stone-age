extends RefCounted
## Read-only delivery stages. The original gate, not helper travel, admits players.
const Rules=preload("res://server/original_quests.gd")
const MARJU="extra/event/marju@1300:70:51"
const KAITE="extra/event/marju01@119:97:88"
const GATE="genout/wpm_120_19_15@120:19:15"
const MAZE=[122,118,119]
static func stage_key(backend) -> Array:
 var map_id:int=backend.automation.position_map
 if map_id not in MAZE:return ["marju",false]
 var npc:Dictionary=backend.original_quests.npc_by_id(KAITE)
 return ["marju",map_id,backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),backend.original_quests.branch_for(npc,backend.session.snapshot()),can_navigate(backend,npc)]
static func can_navigate(backend,npc:Dictionary) -> bool:
 if npc.is_empty():return false
 if int(npc.get("map_id",-1)) not in MAZE:return true
 if backend.automation.position_map!=int(npc.map_id):return false
 if not backend.quest_arrival.has_arrival(backend,int(npc.map_id),backend.automation.position_cell):return false
 if not backend.original_quests.allowed(backend,npc):return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 return not branch.is_empty() and backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty()
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or npc.is_empty():return {}
 if int(npc.get("map_id",-1)) not in MAZE:
  var plain:Dictionary=npc.duplicate(true);plain.events=[]
  return helper.destination(backend,plain,mode)
 if backend.automation.position_map not in MAZE:
  var gate:Dictionary=backend.original_quests.npc_by_id(GATE).duplicate(true)
  if gate.is_empty():return {}
  gate.events=[]
  var target:Dictionary=helper.destination(backend,gate,mode)
  if not target.is_empty():target.npc_id=""
  return target
 if not can_navigate(backend,npc):return {}
 var point:Vector2i=backend.automation.position_cell
 return {"map_id":int(npc.map_id),"cell":[point.x,point.y],"npc_id":str(npc.id)}
static func entry(backend,script:String,index:int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs_by_source(script):
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary) -> void:
 var delivered:=Rules.flag(profile,"ended",37)
 var ended:=Rules.flag(profile,"ended",38)
 var started:=Rules.flag(profile,"now",37)
 var mail:bool=2687 in profile.original_items
 var stone:bool=2697 in profile.original_items
 var inside:bool=int(backend.automation.position_map) in MAZE
 quest.completion_detail="角色50级后替霍特尔村马祖送信。送到卡伊特仅完成37，回马祖领取三种随机武器之一才完成加点项38。原入口须50级且不组队；助手在洞外仅引导到原入口，洞内须沿原迷宫步行，合法到达且符合原分支时仅支持近处原地交谈。出洞回村按原物品与旗标领奖。切绳石与补发保留，宝袋支线尚未开放；奖励精灵魔法仅保留原标签，未生效。自动执行尚未开放。"
 if int(quest.event)==37:
  helper.add_step(backend,profile,quest,"marju:request",entry(backend,"extra/event/marju",0),not started and not delivered and not ended,started or delivered or ended,"向马祖领取邮件（角色50级）")
  var gate:Dictionary=backend.original_quests.npc_by_id(GATE)
  if not gate.is_empty():
   helper.add_step(backend,profile,quest,"marju:gate",{"npc":gate,"branch":gate.branches[0]},started and mail and not delivered and not inside,inside or delivered,"向水田迷宫房子主人申请入洞（50级，须先离队）")
  helper.add_step(backend,profile,quest,"marju:deliver",entry(backend,"extra/event/marju01",0),started and mail and not delivered and inside,delivered,"穿过水田迷宫，把邮件交给卡伊特，取得切绳石")
  if started and not mail and not delivered:
   quest.blocked_reason="邮件已丢失：回马祖处取消再接取；原取消扣1魅力。"
   helper.add_step(backend,profile,quest,"marju:recover",entry(backend,"extra/event/marju",0),true,false,"回马祖取消丢失的邮件委托，再重新接取")
  elif started and mail and stone and not delivered:
   quest.blocked_reason="原交信条件要求未持有切绳石；先处理背包中的切绳石，再交邮件。宝袋支线尚未开放。"
 else:
  helper.add_step(backend,profile,quest,"marju:return",entry(backend,"extra/event/marju",1),delivered and not ended,ended,"送信后回马祖领奖，完成加点项38")
  if not delivered:quest.blocked_reason="先完成马祖送信37；只接邮件或到达迷宫还不能领奖。"
  elif not ended:quest.status="进行中"
 if not ended and int(profile.player.level)<50:quest.blocked_reason="原主链需要角色50级；40级领取切绳石不等于送信或完成任务。"
 for step in quest.steps:
  if str(step.get("npc_id",""))!=KAITE:continue
  var npc:Dictionary=backend.original_quests.npc_by_id(KAITE)
  if inside and (not can_navigate(backend,npc) or backend.original_quests.branch_for(npc,profile)!=step.get("source",{}).get("branch_data",{})):
   step.erase("map_id");step.erase("cell");step.current=false;step.actionable=false
   if not bool(step.get("done",false)):step.label+="（须沿原迷宫步行至近谈位置）"
