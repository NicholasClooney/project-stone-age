extends RefCounted
const Rules=preload("res://server/original_quests.gd")
static func entry(backend, script: String, index: int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var event:=int(quest.event)
 var ended:=Rules.flag(profile,"ended",event)
 var started:=Rules.flag(profile,"now",event)
 var shells:int=profile.original_items.count(2414)
 quest.completion_detail="商人免费提供贝壳；年青人收一颗，有两颗以上给特洛昆、只有一颗给呼拔拔。小猪送信要持有贝壳，鲜花免费，最后保留贝壳。红玉手环实际攻+3防+3敏-3魅+2，原说明数值有误。助手仅送原公开洞口或合法近处原地；须沿哥亚山原路线步行，自动执行尚未开放。"
 if event==6:
  helper.add_step(backend,profile,quest,"goya6:request",entry(backend,"jaruga/event/event06_1",2),not started and not ended,started or ended,"向哥亚山一楼年青人接取贝壳委托")
  var merchant:=0 if shells==0 else (2 if shells==1 else 1)
  helper.add_step(backend,profile,quest,"goya6:shells",entry(backend,"jaruga/event/event06_2",merchant),started and shells<2 and not ended,shells>=2 or ended,"向卡鲁它那的玛丽娜丝商人免费领取两颗贝壳")
  helper.add_step(backend,profile,quest,"goya6:deliver",entry(backend,"jaruga/event/event06_1",0 if shells>=2 else 1),started and shells>0 and not ended,ended,"交一颗贝壳：持两颗以上获特洛昆；仅一颗获呼拔拔")
  if ended and shells==0:helper.add_step(backend,profile,quest,"goya6:replace",entry(backend,"jaruga/event/event06_2",3),true,false,"完成后贝壳丢失：商人免费补一颗，不重发宠物")
 elif event==7:
  helper.add_step(backend,profile,quest,"goya7:request",entry(backend,"jaruga/event/event07_1",1),not started and not ended,started or ended,"携贝壳向乌力斯凯接取送信委托")
  var flower:bool=2424 in profile.original_items
  var letter:bool=2425 in profile.original_items
  helper.add_step(backend,profile,quest,"goya7:flower",entry(backend,"jaruga/event/event07_3",0),started and letter and not flower and not ended,flower or ended,"携信与贝壳向四楼乌力花店免费领取月光花")
  helper.add_step(backend,profile,quest,"goya7:deliver",entry(backend,"jaruga/event/event07_2",0),started and letter and flower and not ended,ended,"把花和信送给山顶的乌力美，完成END7")
  if started and not letter and not ended:quest.blocked_reason="信已丢失：回乌力斯凯处取消并重接；取消按原规则扣1魅力。"
 elif event==8:
  var letter:bool=2426 in profile.original_items
  helper.add_step(backend,profile,quest,"goya8:request",entry(backend,"jaruga/event/event07_2",1),not started and not ended,started or ended,"交完花和信后，再向乌力美领取回信")
  helper.add_step(backend,profile,quest,"goya8:deliver",entry(backend,"jaruga/event/event07_1",0),started and letter and not ended,ended,"携贝壳将回信交给一楼乌力斯凯，领取红玉手环")
  if not Rules.flag(profile,"ended",7):quest.blocked_reason="先把乌力斯凯的信和月光花交给乌力美。"
  if started and not letter and not ended:quest.blocked_reason="回信已丢失：回乌力美处取消并重接；取消按原规则扣1魅力。"
 if event in [7,8] and shells==0 and not ended:quest.blocked_reason="需要携带不可思议的贝壳才能听懂乌力；可先完成哥亚贝壳委托，丢失后找商人补领。"
