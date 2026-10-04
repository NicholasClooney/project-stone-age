extends RefCounted
## Read-only intent selection. OriginalQuests owns admission, arrival and saving.
const Rules=preload("res://server/original_quests.gd")
const JOB_EVENTS={12:3,13:5,24:7,25:8,5:37,9:38}
const YAM="sainasu/event/event03_2@1400:69:89"
const MATI="sainasu/event/event03_1@1300:18:42"
const SKY="jaruga/event/event07_1@20401:14:10"
const FLOWER="jaruga/event/event07_3@20404:44:13"
const BEAUTY="jaruga/event/event07_2@20406:36:34"
const MARJU="extra/event/marju@1300:70:51"
const KAITE="extra/event/marju01@119:97:88"
const GATE="genout/wpm_120_19_15@120:19:15"
const MAZE=[122,118,119]
const RECIPE_EVENTS={"yam_request":3,"yam_deliver":3,"yam_reply":5,"yam_return":5,"goya_request":7,"goya_flower":7,"goya_deliver":7,"goya_reply":8,"goya_return":8,"marju_request":37,"marju_gate":-1,"marju_deliver":38,"marju_return":38}
# Exact audited source index/type/condition/actions, not a generic yes/ok permit.
const RECIPES={
 "yam_request":[YAM,1,"REQUEST","LV>0",{"GetItem":"2416"}],
 "yam_deliver":[MATI,0,"ACCEPT","NOWEV=3&ITEM=2416",{"DelItem":"2416","EndSetFlg":"3"}],
 "yam_reply":[MATI,1,"REQUEST","ENDEV=3",{"GetItem":"2423"}],
 "yam_return":[YAM,0,"ACCEPT","NOWEV=5&ITEM=2423",{"GetItem":"2448","DelItem":"2423","EndSetFlg":"5"}],
 "goya_request":[SKY,1,"REQUEST","LV>0&ITEM=2414",{"GetItem":"2425"}],
 "goya_flower":[FLOWER,0,"ACCEPT","NOWEV=7&ITEM=2414&ITEM=2425&ITEM!=2424",{"GetItem":"2424"}],
 "goya_deliver":[BEAUTY,0,"ACCEPT","NOWEV=7&ITEM=2414&ITEM=2424&ITEM=2425",{"DelItem":"2425,2424","EndSetFlg":"7"}],
 "goya_reply":[BEAUTY,1,"REQUEST","LV>0&ENDEV=7&ITEM=2414",{"GetItem":"2426"}],
 "goya_return":[SKY,0,"ACCEPT","NOWEV=8&ITEM=2414&ITEM=2426",{"GetItem":"1206","DelItem":"2426","EndSetFlg":"8"}],
 "marju_request":[MARJU,0,"REQUEST","LV>49&ENDEV!=38",{"GetItem":"2687"}],
 "marju_gate":[GATE,-1,"FREEWARP","LV>49",{"Warp":"122,6,5"}],
 "marju_deliver":[KAITE,0,"REQUEST","NOWEV=37&LV>49&ITEM=2687&ITEM!=2697",{"DelItem":"2687","GetItem":"2697","EndSetFlg":"37"}],
 "marju_return":[MARJU,1,"ACCEPT","ENDEV=37&LV>49",{"GetRandItem":"2688,2689,2690","EndSetFlg":"38"}]
}
static func supports(job_id:int)->bool:return JOB_EVENTS.has(job_id)
static func manual(reason:String)->Dictionary:return {"status":"manual","reason":reason}
static func select(b,job_id:int)->Dictionary:
 if not supports(job_id):return manual("此任务尚未开放自动推进。")
 var event:int=JOB_EVENTS[job_id]
 if event not in b.quest_catalog.enabled_events:return manual("此任务尚未开放。")
 # The imported job identity must still agree with the reviewed event.
 if not b.quest_catalog.jobs.any(func(job):return int(job.id)==job_id and int(job.event)==event):return manual("原任务编号已改变，请手动处理。")
 var p:Dictionary=b.session.snapshot()
 if Rules.flag(p,"ended",event):return {"status":"done"}
 var current_map:int=b.automation.position_map
 if (current_map in MAZE or current_map in range(20401,20407)) and not b.quest_arrival.has_arrival(b,current_map,b.automation.position_cell):
  return manual("当前洞内位置缺少原路到达记录；请手动从原入口重新进入后再自动推进。")
 var started:bool=Rules.flag(p,"now",event)
 var items:Array=p.original_items
 match event:
  3,5:
   if event==5 and not Rules.flag(p,"ended",3):return manual("请先完成亚姆送斧头任务3。")
   var item:int=2416 if event==3 else 2423
   if started and item not in items:return manual("委托物品已丢失或正在装备；请手动处理，自动推进不会取消任务或扣魅力。")
   return step(b,p,"yam_deliver" if started else "yam_request") if event==3 else step(b,p,"yam_return" if started else "yam_reply")
  7,8:
   if 2414 not in items:return manual("需要不可思议的贝壳才能听懂乌力；请手动取得，自动推进不执行换宠任务6。")
   if event==8 and not Rules.flag(p,"ended",7):return manual("请先完成送花和信任务7。")
   if not started:return step(b,p,"goya_request" if event==7 else "goya_reply")
   if (2425 if event==7 else 2426) not in items:return manual("信已丢失；请手动取消并重新领取（原取消扣1魅力）。")
   if event==8:return step(b,p,"goya_return")
   return step(b,p,"goya_deliver" if 2424 in items else "goya_flower")
  37,38:
   if int(p.player.level)<50:return manual("马祖送信主链需要角色50级。")
   if event==38:
    if not Rules.flag(p,"ended",37):return manual("请先完成马祖送信37；到达迷宫不等于交信完成。")
    return step(b,p,"marju_return")
   if not started:return step(b,p,"marju_request")
   if 2687 not in items:return manual("邮件已丢失；请手动取消重接（原取消扣1魅力）。")
   if 2697 in items:return manual("原交信要求未持有切绳石；请手动处理已有切绳石。宝袋不在自动推进范围内。")
   return step(b,p,"marju_deliver" if current_map in MAZE else "marju_gate")
 return manual("未知任务分支，请手动处理。")

static func step(b,p:Dictionary,key:String)->Dictionary:
 var recipe:Array=RECIPES[key]
 var npc:Dictionary=b.original_quests.npc_by_id(str(recipe[0]))
 if npc.is_empty():return manual("原任务人物不可用，请手动处理。")
 var branch:Dictionary=b.original_quests.branch_for(npc,p)
 if int(branch.get("event",-999))!=int(RECIPE_EVENTS[key]):return manual("原分支事件已改变，请手动处理。")
 for field in branch:
  if field not in ["event","type","condition","texts","actions","source_branch_index","source_line","enabled","events","source","source_fields","source_rule"]:return manual("原分支含未审核的选择或行为，请手动处理。")
 if branch.is_empty() or int(branch.get("source_branch_index",-1))!=int(recipe[1]) or str(branch.get("type",""))!=str(recipe[2]) or str(branch.get("condition",""))!=str(recipe[3]) or branch.get("actions",{})!=recipe[4]:
  return manual("当前原分支不符合已审核送物步骤；请检查前置、装备或背包后手动处理。")
 var worn_hint:String=Rules.worn_item_hint(p,str(branch.condition))
 if not worn_hint.is_empty():return manual(worn_hint)
 if branch.has("spoken_keyword") or branch.has("keyword") or bool(branch.get("project_pet_selection",false)) or npc.has("kind"):
  return manual("口令、服务或选宠需由玩家处理。")
 if str(branch.type)=="REQUEST" and Rules.flag(p,"now",int(branch.event)):return manual("此分支会取消已接任务，请手动处理。")
 if str(branch.type)=="FREEWARP" and b.quest_visit_guard.is_valid() and not str(b.quest_visit_guard.call()).is_empty():return manual("原迷宫入口不能组队进入，请先离队。")
 var candidate:Dictionary=p.duplicate(true)
 Rules.remove_items(candidate,str(branch.actions.get("DelItem","")),str(branch.get("item_deletion_scope",""))=="bag")
 var slots:int=Rules.item_list(str(branch.actions.get("GetItem",""))).size()+(1 if branch.actions.has("GetRandItem") else 0)
 if Rules.Session.bag_slots(candidate)+slots>15:return manual("道具栏空间不足，请整理后重新自动推进。")
 return {"status":"step","step":{"id":"delivery:"+key,"npc_id":str(npc.id),"map_id":int(npc.map_id),"cell":npc.cell.duplicate(),"current":true,"done":false,"actionable":true,"label":"沿原路前往"+str(npc.name),"auto_choices":["yes"] if str(branch.type)=="FREEWARP" else ["yes","ok"],"source":{"npc_id":str(npc.id),"branch":npc.branches.find(branch),"type":str(branch.type),"condition":str(branch.condition),"actions":branch.actions.duplicate(true),"branch_data":branch.duplicate(true)}}}
