extends RefCounted
## First dependency slice only: no production rebirth until all owners integrate.
const KIND := "original_transmigration"
const NPC_ID := "777/ten.arg@32021:31:28"
const CLOSED := "人物转生第三阶段尚未开放；本次不会扣除宠物或改变属性。"
var pending:Dictionary={}
func reset()->void:pending.clear()
func command(_backend,_command:Dictionary)->Dictionary:
 return {"ok":false,"reason":CLOSED}
func open(_backend,_npc:Dictionary)->Dictionary:
 return {"ok":false,"reason":CLOSED}
