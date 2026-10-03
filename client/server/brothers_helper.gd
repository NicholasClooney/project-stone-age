extends RefCounted
const Rules=preload("res://server/original_quests.gd")
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var event:=int(quest.event)
 quest.completion_detail="按本地实际原脚本：两链无先后互锁。首次镜2547归还发金羊；丢镜补发2532不发金羊。奖励装备属性和精灵魔法尚未实现；守卫使用现有战斗AI，原战术权重与异常技未恢复。助手瞬移是项目便利，会绕过行走与守卫；未开放复杂自动任务。"
 var ids:Array=[]
 match event:
  28:
   ids=["giiru/event/ev28_0"]
   # Preserve all answers, including wrong ones. The five question signs
   # explain what is being asked; the other signs remain on the actual map.
   for i in range(1,24):ids.append("giiru/event/ev28_%d"%i)
   ids.append("giiru/event/ev28_end")
  31:
   ids=["giiru/event/ev28_0","giiru/event/ev28_end","genout/wpm_31705_25_8"]
   for i in range(1,6):ids.append("300/sb_5b%d.arg"%i)
   for i in range(1,6):ids.append("giiru/event/ev28_ed%d"%i)
  30:ids=["giiru/event/event30_1","giiru/event/event30_2","giiru/event/event30_3","giiru/event/event30_4","king/event69_1"]
  29:ids=["giiru/event/event30_2","giiru/event/event30_7","genout/wpm_31910_8_9","giiru/event/event30_6"]
  54:ids=["giiru/event/event30_2","king/event69_1"]
 # Resolve one authoritative projection per snapshot, rather than cloning
 # the whole catalog for every sign while walking past nearby NPCs.
 backend.original_quests.refresh_npc_state()
 var by_id:Dictionary={}
 for npc in backend.quest_catalog.active_npcs():by_id[str(npc.id)]=npc
 for id in ids:
  var npc:Dictionary=by_id.get(str(id),{})
  if npc.is_empty():continue
  var branch:Dictionary=backend.original_quests.branch_for(npc,profile)
  var live:=not branch.is_empty()
  if branch.is_empty():branch=npc.branches[0]
  var caption:String=str(npc.name)+"："+Rules.message(branch.texts,"AcceptMsg")
  if str(branch.type)=="REQUEST":caption=str(npc.name)+"："+Rules.message(branch.texts,"RequestMsg")
  if caption.length()>90:caption=caption.left(90)+"…"
  caption=caption.replace("\n"," ").strip_edges()
  helper.add_step(backend,profile,quest,"brothers:"+str(id),{"npc":npc,"branch":branch},live and quest.status!="已完成",quest.status=="已完成",caption)
 if event in [29,54]:
  var held:bool=2548 in profile.original_items
  quest.steps.append({"id":"golden:eye","npc_id":"","map_id":31907,"cell":[24,43],"current":Rules.flag(profile,"now",54) and not held and not Rules.flag(profile,"ended",29),"done":held or Rules.flag(profile,"ended",29),"actionable":2547 in profile.original_items or 2532 in profile.original_items,"label":"携心性之镜在采石场六楼遇敌，击败精灵的使者取得真实之眼；选错使者会交掉眼并传回矿坑","source":{"type":"encounter","area_id":373,"area_rect":[0,0,59,49],"enemy_id":1060}})
 if event in [29,30,54] and not Rules.flag(profile,"ended",4):quest.blocked_reason="原任务需要先完成成人仪式。"
 if event==28 and int(profile.player.level)<=30:quest.blocked_reason="原接取条件：等级31以上。"
 if event==54 and 2532 in profile.original_items and not 2547 in profile.original_items:quest.blocked_reason="你持有补发镜子；按原分支，归还只结束任务，不发黄金羚羊。"

 if event in [28,31]:preload("res://server/brothers_arrival_helper.gd").project(helper,backend,quest)
