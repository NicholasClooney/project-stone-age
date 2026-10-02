extends RefCounted
## Exchange steps; registered only once the original gates/battles are connected.
const Rules=preload("res://server/original_quests.gd")
static func entry(backend, script: String, index: int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",9)
 var now9:=Rules.flag(profile,"now",9)
 var now10:=Rules.flag(profile,"now",10)
 var now11:=Rules.flag(profile,"now",11)
 var end10:=Rules.flag(profile,"ended",10)
 var end11:=Rules.flag(profile,"ended",11)
 var end12:=Rules.flag(profile,"ended",12)
 var stone10:bool=2419 in profile.original_items
 var stone11:bool=2420 in profile.original_items
 quest.completion_detail="成人仪式完成且等级30以上可接。取回两村守护石后，首次须先交卡坦石，再交霍特尔石，最后回柯尔克村姑领取黄色大首饰；只有最后回报才完成整项日志。洞窟暗号为“在卡坦有梦德”。助手瞬移是项目便利；自动执行尚未开放。"
 helper.add_step(backend,profile,quest,"munde9:request",entry(backend,"sainasu/event/event09",1),not now9 and not ended,now9 or ended,"向柯尔克村姑接取委托")
 helper.add_step(backend,profile,quest,"munde11:request",entry(backend,"sainasu/event/event11",2 if now10 else 3),now9 and not now11 and not end11,now11 or end11,"向卡坦青年了解守护石")
 helper.add_step(backend,profile,quest,"munde10:request",entry(backend,"sainasu/event/event10",2 if now11 else 3),now9 and not now10 and not end10,now10 or end10,"向霍特尔村姑了解守护石")
 helper.add_step(backend,profile,quest,"munde9:gate",entry(backend,"genout/wpm_100_443_127",-1),now9 and now10 and now11 and not stone10 and not stone11 and not end12,end12,"向井边盗贼说出原暗号：在卡坦有梦德")
 helper.add_step(backend,profile,quest,"munde9:battle",entry(backend,"100/sb_go.arg",-1),now9 and now10 and now11 and not stone10 and not stone11 and not end12,end12,"挑战悟与唐的原四敌队伍；胜利后传送通过守卫")
 helper.add_step(backend,profile,quest,"munde12:stones",entry(backend,"sainasu/event/event12",0),now9 and now10 and now11 and not stone10 and not stone11 and not end12,stone10 or stone11 or end12,"通过洞窟暗号与悟唐守卫后，向梦德领取两村守护石")
 helper.add_step(backend,profile,quest,"munde11:deliver",entry(backend,"sainasu/event/event11",0 if end10 else 1),now11 and stone11 and not end11,end11,"首次先交卡坦守护石，领取芙雷雅铠并增加1魅力")
 helper.add_step(backend,profile,quest,"munde10:deliver",entry(backend,"sainasu/event/event10",0),end11 and now10 and stone10 and not end10,end10,"再交霍特尔守护石，领取勾玉并完成两村回报")
 helper.add_step(backend,profile,quest,"munde9:deliver",entry(backend,"sainasu/event/event09",0),end10 and end11 and end12 and not ended,ended,"回柯尔克村姑处领取黄色大首饰最终谢礼")
 if not ended and (int(profile.player.level)<30 or not Rules.flag(profile,"ended",4)):quest.blocked_reason="需要等级30以上，并先完成成人仪式。"
