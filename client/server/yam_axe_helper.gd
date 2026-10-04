extends RefCounted
const Rules=preload("res://server/original_quests.gd")
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var event:=int(quest.event)
 var ended:=Rules.flag(profile,"ended",event)
 var started:=Rules.flag(profile,"now",event)
 var item:=2416 if event==3 else 2423
 var held:bool=item in profile.original_items
 var request:Dictionary=helper.pick(backend,profile,helper.candidates(backend,event,"GetItem",item))
 var delivery:Dictionary=helper.pick(backend,profile,helper.candidates(backend,event,"DelItem",item))
 helper.add_step(backend,profile,quest,"yam%d:request"%event,request,not started and not ended,started or ended,"向亚姆亚姆领取要送给马提的斧头" if event==3 else "向马提领取给亚姆亚姆的感谢信")
 helper.add_step(backend,profile,quest,"yam%d:deliver"%event,delivery,started and held and not ended,ended,"先卸下临时斧，再交给马提" if event==3 else "把马提的信交给亚姆亚姆，领取改良斧头")
 quest.completion_detail="送斧头完成END3后还要接取回信，交回信才完成END5。临时斧20级、改良斧25级可装备；本项目丢弃直接删除，尚无地面拾取。助手单步瞬移是项目便利；自动推进沿原路步行，普通遇敌沿用现有自动战斗，失败或需人工处理时结束，处理后可重新启动。"
 if event==5 and not Rules.flag(profile,"ended",3):quest.blocked_reason="先把亚姆亚姆的斧头送到马提处。"
 if started and not held and not ended:
  quest.blocked_reason="委托物品已丢失：与发放者交谈取消，再重新接取；取消按原规则扣1魅力。"
  helper.add_step(backend,profile,quest,"yam%d:recover"%event,request,true,false,"物品丢失：与发放者交谈取消，再重新接取")
