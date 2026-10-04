extends RefCounted
## UNRUN. End at END27; never buy replacement ticket or enter floor six.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=14:return hold("unsupported_job","仅矿工job14。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",27):return {"status":"done"}
 if 2533 in held:return hold("claim_ticket","原交2533得2527/END27即停；不买补票。","giiru/event/giruev2_1",23)
 if not Rules.flag(p,"now",27):
  if int(p.player.level)<=29:return hold("level","原LV>29。")
  return hold("request","待原REQUEST；map300入口有未决A路径，不便利入矿。","giiru/event/giruev2_1",41)
 if 2535 in held:return hold("wait_boss","巴卡斯确认人工、原胜利/奖励保存后继续；不清隐藏状态重开。","300/sb_bac.arg",5)
 if 2534 in held:return hold("exchange_ore","源要求NOW27且2534，不能额外臆加持2536条件；原事务删2534/2536得2535。","giiru/event/giruev2_2",27)
 if not 2536 in held:return hold("claim_lunch","原REQUEST领2536，不买票。","giiru/event/giruev2_2",43)
 var result:=hold("loot_contract_missing","矿石完整源签名/区域和执行未冻结；不能借2760签名。")
 result["review_needed"]={"item_id":2534,"count":1,"group_id":508,"enemy_id":1043,"map_ids":[31801,31802,31803]}
 return result
