extends RefCounted
## Coordinator-confirmed scope: existing job22, NOW18 allowed, stop at axe+END19.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="jaruga/event/20501ev1",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=22:return hold("unsupported_job","哈恩限job22内部阶段；job19属于五兄弟。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",19):
  if 2465 in held:return {"status":"done"}
  return hold("missing_axe","已END19但未持斧头；不得CLEAN19重领或进入额外循环。")
 if 2465 in held:return hold("inconsistent_axe","持斧而未END19，等待核对；不交斧开启END18后续。")
 if not 2466 in held:
  if Rules.flag(p,"ended",18) or 2467 in held:return hold("commission_unavailable","原委托源已被后续分支遮蔽；不清旗、不采木。")
  if Rules.flag(p,"now",18):return hold("replace_commission","允许原NOW18补委托；精确MESSAGE合同待核。","jaruga/event/20501ev3",42)
  if int(p.player.level)<=14:return hold("level","原委托LV>14。")
  return hold("commission","允许原REQUEST开始NOW18；仅前置委托，不继续END18交斧。","jaruga/event/20501ev3",50)
 if not Rules.flag(p,"now",19):return hold("request_axe","待持2466原REQUEST，禁止购买额外壶。","jaruga/event/20501ev1",40)
 if 2464 in held:return hold("claim_axe","待原ACCEPT交水/委托并消费壶；取得2465且END19后停止。","jaruga/event/20501ev1",15)
 if 2463 in held:return hold("fill_water","待水管理员原ACCEPT及保护路线。","jaruga/event/20501ev2",15)
 return hold("replace_pot","待原MESSAGE补壶合同；不代买壶。","jaruga/event/20501ev1",26)
