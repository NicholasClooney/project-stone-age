extends RefCounted
## UNRUN. Static answers d878 exist; keyword/Warp/Charm execution is NOT implied.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if job_id!=8:return hold("unsupported_job","仅梦德job8。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",9):return {"status":"done"}
 if Rules.flag(p,"ended",10) and Rules.flag(p,"ended",11) and Rules.flag(p,"ended",12):
  return hold("final_reward","原最终ACCEPT待绑定；不重复领石。","sainasu/event/event09",3)
 if not Rules.flag(p,"now",9):
  if int(p.player.level)<=29 or not Rules.flag(p,"ended",4):return hold("prerequisite","原LV>29且END4。")
  return hold("request9","待原REQUEST及路线。","sainasu/event/event09",14)
 if not Rules.flag(p,"ended",11) and not Rules.flag(p,"now",11):
  return hold("request11","卡坦原REQUEST，按当前NOW10精确匹配分支。","sainasu/event/event11",29 if Rules.flag(p,"now",10) else 41)
 if not Rules.flag(p,"ended",10) and not Rules.flag(p,"now",10):
  return hold("request10","霍特尔原REQUEST，按当前NOW11精确匹配分支。","sainasu/event/event10",28 if Rules.flag(p,"now",11) else 41)
 if 2420 in held and Rules.flag(p,"now",11) and not Rules.flag(p,"ended",11):
  return hold("return_stone_charm","原Charm1不能省略，待核心精确事务合同。","sainasu/event/event11",4 if Rules.flag(p,"ended",10) else 16)
 if 2419 in held and Rules.flag(p,"ended",11) and Rules.flag(p,"now",10) and not Rules.flag(p,"ended",10):
  return hold("return_stone10","交2419原ACCEPT，原END10/12。","sainasu/event/event10",4)
 if 2419 in held or 2420 in held or Rules.flag(p,"ended",10) or Rules.flag(p,"ended",11):
  return hold("partial_state","部分石/事件组合须精确源分支核对；不清旗补物。")
 if b.automation.position_map==11107:
  return hold("boss_and_stones","须原合法区域/人工悟唐胜利保存后才领双石；当前位置不证明胜利，不进入风41/42。","sainasu/event/event12",4)
 return hold("keyword_route","复用d878公开口令resolver；四门执行/原Warp receipt未冻结，王确认人工。","genout/wpm_100_443_127",1)
