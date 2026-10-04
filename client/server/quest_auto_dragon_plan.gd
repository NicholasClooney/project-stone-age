extends RefCounted
## UNRUN. No dragon loot source signature or gate executor is frozen.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=26:return hold("unsupported_job","仅龙洞job26。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",17):return {"status":"done"}
 if not Rules.flag(p,"now",17):
  if 2505 in held:return hold("inconsistent_token","原REQUEST要求无2505；不丢弃或伪造NOW17。")
  return hold("request","原一层REQUEST及合法原门路线待绑定。","jaruga/event/event17_4",13)
 if not 2505 in held:return hold("replace_token","仅原补领ACCEPT，不借金布伊权限。","jaruga/event/event17_4",3)
 for item in [2457,2458,2459]:
  if not item in held:
   var result:=hold("loot_contract_missing","龙洞完整源签名/ledger执行未冻结；2760合同不可复用。")
   result["review_needed"]={"item_id":item,"count":1,"map_id":{2457:20804,2458:20805,2459:20806}[item],"group_id":{2457:404,2458:405,2459:406}[item],"enemy_id":{2457:562,2458:560,2459:559}[item]}
   return result
 return hold("gate_and_manual_reward","三玉门原Warp需独立hook/合法区域；通过后玩家选三NPC之一，不默认衣/枪/铠。","genout/wpm_20807_11_37",1)
