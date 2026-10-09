extends "res://server/quest_auto.gd"
# Exact c4d0308f prepare_start.
func prepare_start(b,command:Dictionary) -> Dictionary:
 if b._quest_auto_stop_operation_call!=null:return b._reject("自动任务正在停止，请稍后重试。")
 if running:return b._reject("自动任务已在运行。")
 var id=command.get("quest_id",-1)
 if not (id is int or id is float) or float(id)!=floor(float(id)):return b._reject("无效任务编号。")
 var quest:=row(b,int(id))
 if quest.is_empty() or not (_supports_automatic_start(int(id),int(quest.event)) or (b._doctor_request_enabled() and int(id)==6 and int(quest.event)==15)) or not int(quest.event) in b.quest_catalog.enabled_events:return b._reject("此任务尚未开放自动推进。")
 if b._doctor_request_enabled() and int(id)==6:
  var peer:Variant=command.get("_quest_connection")
  if not peer is int or peer==-1 or not b._fee_bindings.get(peer) is RefCounted:return b._reject("博士首请求需要当前可信连接。")
 if b.battle_open or not b.session._pending.is_empty() or b.automation.running or b.automation.hunt_running or b.automation.flow_active() or not b.original_quests.pending.is_empty():return b._reject("当前正忙。")
 if b.quest_visit_guard.is_valid():
  var reason:=str(b.quest_visit_guard.call())
  if not reason.is_empty():return b._reject(reason)
 if str(command.get("client","")).is_empty():return b._reject("缺少发起设备。")
 if int(id)==2:
  if not command.get("_quest_connection") is int or int(command._quest_connection)==-1:return b._reject("缺少可信发起连接。")
  var admitted:Dictionary=source_admission(b)
  if not admitted.ok and not b._fee_lobby_ticket.propose(b):return b._reject(str(admitted.reason))
  return {"ok":true,"source":true,"quest_id":2,"client":str(command.client),"connection":int(command._quest_connection)}
 if int(quest.event)==4 and int(b.session._profile.player.level)<30:return b._reject("原成人仪式入口需要等级30；自动任务不能绕过等级门。")
 var first:Dictionary=strict_select(b,int(id),bool(quest.get("can_restart",false)))
 if first.get("status","")!="step" or not safe_step(first.get("step",{}),int(id),bool(quest.get("can_restart",false))):return b._reject(str(first.get("reason",quest.get("blocked_reason","")))+" 当前没有可自动执行的已审核原任务步骤。")
 return {"ok":true,"source":false,"quest_id":int(id),"client":str(command.client),"connection":int(command.get("_quest_connection",-1)),"clean":bool(quest.get("can_restart",false)),"first":first.step.duplicate(true)}
