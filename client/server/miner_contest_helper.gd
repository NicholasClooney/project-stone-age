extends RefCounted
## Read-only event27 stages. Entry to floor six always uses the original ticket NPC.
const Rules=preload("res://server/original_quests.gd")
static func entry(backend,script:String,index:int=-1) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",27)
 var started:=Rules.flag(profile,"now",27)
 var items:Array=profile.original_items
 quest.completion_detail="30级起向五楼帖尼姆接取委托，向巴巴洛领采矿证，在矿山一至三楼原条件遭遇取得矿石，再换参赛证、挑战巴卡斯并交回采矿权证明。领奖才写END27。六楼每次进入收一张许可证，完成后可用1000石币补购。原版NPC为全服共享，本项目按角色各自计算；胜后消失，严格超过300秒复现，服务器重启复位。敌方使用现有AI，原特殊技能未恢复；原补票条件保留缺表物品2391的否定检查，不提供该物品；助手仅到公开原洞口或合法近处原地，须沿矿山原楼梯步行，六楼仍须原NPC验票；自动执行未开放。"
 helper.add_step(backend,profile,quest,"miner27:request",entry(backend,"giiru/event/giruev2_1",3),not started and not ended,started or ended,"向五楼帖尼姆报名代赛（角色至少30级）")
 helper.add_step(backend,profile,quest,"miner27:permit",entry(backend,"giiru/event/giruev2_2",5),started and not ended and not (2536 in items or 2534 in items or 2535 in items or 2533 in items),2536 in items or 2534 in items or 2535 in items or 2533 in items or ended,"向巴巴洛领取采矿许可证")
 var mining:=started and 2536 in items and not (2534 in items or 2535 in items or 2533 in items) and not ended
 var ore_step:Dictionary={"id":"miner27:ore","npc_id":"","current":mining,"done":2534 in items or 2535 in items or 2533 in items or ended,"actionable":false,"label":"携采矿许可证，在矿山一至三楼走动遇敌，击败阿思玛鲁原石取得矿石；不保证每次遭遇都是原石。","source":{"type":"miner_contest_encounter","enemy_id":1043,"group_id":508,"item_id":2534,"requires_item":2536}}
 var area:Dictionary=backend.encounter_catalog.area_at(31801,Vector2i(37,48))
 if not area.is_empty():
  var point:Dictionary=helper.geometric_destination(backend,{"id":"","map_id":31801,"cell":[37,48],"area_rect":area.rect},"near")
  if not point.is_empty():
   ore_step.map_id=31801;ore_step.cell=[37,48];ore_step.actionable=mining
   ore_step.source={"type":"encounter","area_id":int(area.id),"area_rect":area.rect.duplicate(),"enemy_id":1043,"group_id":508,"item_id":2534,"requires_item":2536}
 quest.steps.append(ore_step)
 helper.add_step(backend,profile,quest,"miner27:qualify",entry(backend,"giiru/event/giruev2_2",3),started and 2534 in items and not (2535 in items or 2533 in items) and not ended,2535 in items or 2533 in items or ended,"交矿石与采矿证，领取参赛许可证")
 helper.add_step(backend,profile,quest,"miner27:battle",entry(backend,"300/sb_bac.arg"),2535 in items and not (2533 in items) and not ended,2533 in items or ended,"携参赛证挑战矿工巴卡斯；获胜取得采矿权证明")
 helper.add_step(backend,profile,quest,"miner27:reward",entry(backend,"giiru/event/giruev2_1",1),2533 in items and not ended,ended,"向帖尼姆交采矿权证明，领取六楼许可证并完成END27")
 if ended:
  helper.add_step(backend,profile,quest,"miner27:buy",entry(backend,"giiru/event/giruev2_1",0),not 2527 in items,2527 in items,"可选：花1000石币购买一张六楼入场许可证")
 helper.add_step(backend,profile,quest,"miner27:enter",entry(backend,"genout/wpm_31805_22_4"),2527 in items,false,"向五楼入场管理人交一张许可证，进入六楼")
 if int(profile.player.level)<30 and not started and not ended:quest.blocked_reason="先达到角色30级。"
