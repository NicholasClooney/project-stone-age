extends "res://server/quest_auto.gd"
## Exact d6691c7f caller bodies in candidate environment.
func advance_source(b)->void:
 if b._fee_lobby_ticket.advance(b):return
 if phase=="source_dialogue":
  source_reply(b,source_next(b))
  return
 if phase!="travel":return
 var selected:Dictionary=SourcePlan.select(b,2)
 if selected.get("status")=="done":stop(b,"原金布伊任务已完成。");return
 if selected.get("status")!="step":handoff(b,str(selected.get("reason","原源路线不可用。")));return
 var proposal:Dictionary=selected.step
 var checked:Dictionary=Source.validate_step(b,2,proposal)
 if not checked.ok:handoff(b,str(checked.reason));return
 if source_frame!=null:
  source_frame.cancel();source_frame=null
 if identity.step_id!=str(proposal.id):
  var previous_identity:Dictionary=identity.checkpoint()
  var previous_connection:int=connection
  # Clearing an old receipt must not follow a stale automation position.
  b.emit_event({"type":"auto_status","status":b.automation.status()})
  if not running or detached or connection!=previous_connection or identity.checkpoint()!=previous_identity:return
  clear_motion();navigation.clear()
 step=proposal.duplicate(true);identity.select_step(str(step.id))
 execution_mode="A"
 if step.action=="walk_portal":
  if not b.original_quests.pending.is_empty():handoff(b,"原对话尚未结束。");return
  source_walk(b,navigation.next_portal(b,step.portal))
  return
 var npc:Dictionary=checked.npc
 var offset:Vector2i=b.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if b.automation.position_map==int(npc.map_id) and maxi(absi(offset.x),absi(offset.y))<=2:
  source_reply(b,source_open(b,step))
 else:source_walk(b,navigation.next(b,npc))
func source_reply(b,reply:Dictionary)->void:
 if not running:return
 if not reply.get("ok",false):handoff(b,str(reply.get("reason","原服务失败。")));return
 if detached:return
 if not reply.get("source_commit",{}).get("continued",false):handoff(b,"原服务调用身份已失效。");return
 if reply.get("dialogue") is Dictionary:
  if source_frame==null or source_frame.page.is_empty():handoff(b,"原公开对白已变化。");return
  phase="source_dialogue"
 elif reply.get("closed",false):
  phase="landing" if reply.get("source_commit",{}).get("warp",false) else "travel"
  source_after_landing="travel";waited=0.0
 else:handoff(b,"原服务未返回可审核的后续。");return
 b.publish()
func handoff(b,reason:String)->void:
 var call:Dictionary=transition_frame(b)
 call.identity.revision+=1
 stop(b,reason)
 if not transition_current(b,call):return
 phase="manual"
 pause_reason=reason
 b.publish()
