extends RefCounted
## UNRUN stage draft, base7f1a891a. Source execution/route binding not frozen.
const Rules=preload("res://server/original_quests.gd")
const SOURCE="sainasu/event/event13_1"
static func hold(stage:String,reason:String,source_key:String=SOURCE,line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":source_key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=10:return hold("unsupported_job","仅萨顿job10。")
 var p:Dictionary=b.session._profile
 if Rules.flag(p,"ended",13):return {"status":"done"}
 if not Rules.flag(p,"now",13):
  if int(p.player.level)<=15:return hold("level","原委托要求LV>15。")
  return hold("request","待绑定原REQUEST及合法路线；不得调用CLEAN13。",SOURCE,28)
 var held:Array=p.original_items
 if 2428 in held and 2429 in held and 2430 in held:
  return hold("return_treasures","待精确ACCEPT事务；消三宝及足迹，原END13，项目另补END14。",SOURCE,9)
 if not 2431 in held:return hold("replace_footprint","待精确MESSAGE补足迹合同，不泛放MESSAGE。",SOURCE,20)
 for index in range(3):
  if not (2428+index) in held:
   return hold("wait_boss","王确认由玩家操作；缺宝不代表王可重开，须原隐藏/到达校验。","100/sb_nusu%d.arg"%(index+1))
 return hold("unknown","源状态无法唯一确定。")
