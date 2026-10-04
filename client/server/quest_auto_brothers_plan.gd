extends RefCounted
## UNRUN. Five statues use yes -> ok; no quiz indices, private answers or paper injection.
const Rules=preload("res://server/original_quests.gd")
static func hold(stage:String,reason:String,key:String="",line:int=0)->Dictionary:
 return {"status":"manual","stage":stage,"reason":reason,"required_source":{"key":key,"line":line}}
static func select(b,job_id:int)->Dictionary:
 if not job_id in [18,19]:return hold("unsupported_job","五兄弟仅job18/19。")
 var p:Dictionary=b.session._profile
 var held:Array=p.original_items
 if Rules.flag(p,"ended",28 if job_id==18 else 31):return {"status":"done"}
 if job_id==18:
  if not Rules.flag(p,"now",28):
   if int(p.player.level)<=30:return hold("level","原LV>30。")
   return hold("request28","原REQUEST待绑定。","giiru/event/ev28_0",11)
  for index in range(5):
   var paper:=2507+index*2
   if not paper in held:
    var statue:int=[5,8,12,15,19][index]
    return hold("statue_contract_missing","完整公开题/全选项及精确原yes→ok替换分支尚未接线；不读私有答案，禁止ev28_end删纸MESSAGE探测。","giiru/event/ev28_%d"%statue)
  return hold("claim_crystal","齐五正纸原ACCEPT需完整分支事务；绝不talk失败删纸分支。","giiru/event/ev28_end",11)
 if not Rules.flag(p,"ended",28):return hold("prerequisite","须END28，不自动启动18。")
 if not Rules.flag(p,"now",31):return hold("request31","原持/缺水晶两个REQUEST须核完整当前分支，不授proof。","giiru/event/ev28_end",22)
 if not 2517 in held:return hold("missing_crystal","原水晶可能logout消失；补领须精确原分支，不恢复proof。","giiru/event/ev28_end",22)
 return hold("trap_boss_manual_reward","精确六楼门/陷阱、人工Boss胜后Warp、五NPC玩家选择/GetPet全字段均待hook；不自动选第五守卫或奖励。","genout/wpm_31705_25_8",1)
