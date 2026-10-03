extends "res://tests/quest_arrival_transactions_test.gd"
const FinalRoute=preload("res://tests/support/transmigration_arrival_route.gd")
const FIRST="transmigration_first_boss"
const LAST="transmigration_final_boss"
func final_backend():
 var b=fresh();FinalRoute.install(b)
 # Prior completed chains are profile fixtures; neither these END flags nor
 # catalog installation grants any current arrival or stage.
 for e in [39,40,42,46]:Rules.set_flag(b.session._profile,"ended",e,true)
 return b
func actual_guard(b,source:String,stage:String)->void:
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":FinalRoute.npc(b,source).id})
 check(r.get("ok",false) and choose(b,r,"yes").get("ok",false) and b.battle_open,"source guardian begins: "+source)
 if not b.battle_open:return
 var expected:Array=FinalRoute.npc(b,source).branches[0].guard.enemy_ids.map(func(value):return int(value))
 check(b.session._pending.enemies.map(func(enemy):return int(enemy.source_enemy_id))==expected,"exact original five/ten enemy order retained")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://no-final-arrival-parent/save.json"
 fight(b)
 check(b.session.snapshot()==before and not b.quest_arrival.has_stage(b,stage),"failed battle save never awards "+stage)
 b.save_path=""
 check(b.handle({"type":"battle_close"}).get("ok",false),"real battle save retries and closes")
 check(b.quest_arrival.has_stage(b,stage),"stage only after actual saved victory Warp: "+stage)
func lan_last_gate(b)->void:
 root.add_child(b)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"two-device last gate server uses ephemeral port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"both devices connect to same authoritative route")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var id:String=str(FinalRoute.npc(b,"genout/wpm_32021_31_51").id)
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":id})
 var second:Dictionary=await request(links[1],{"type":"quest_talk","npc_id":id})
 check(first.has("dialogue") and second.has("dialogue"),"both devices reach same actual last gate")
 if first.has("dialogue") and second.has("dialogue"):
  check(not (await request(links[0],{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"})).get("ok",false),"new device dialogue supersedes old original gate token")
  var result:Dictionary=await request(links[1],{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
  if result.has("dialogue"):result=await request(links[1],{"type":"quest_choose","token":result.dialogue.token,"choice":"ok"})
  check(result.get("ok",false),"second device commits actual original last gate")
 for link in links:link.close()
 links=[];server.stop();server.queue_free();root.remove_child(b)
func run()->void:
 var b=final_backend()
 var inside:Dictionary=FinalRoute.npc(b,"genout/wpm_300_108_225")
 b.automation.position_changed(300,Vector2i(108,226))
 check(not b.handle({"type":"quest_talk","npc_id":inside.id}).get("ok",false),"project arrival at second original gate cannot launder skipped outer gate")
 b.automation.position_changed(300,Vector2i(102,228))
 b.save_path="user://no-final-arrival-parent/save.json"
 check(not FinalRoute.commit(b,"genout/wpm_300_103_228") and b.automation.position_cell==Vector2i(102,228),"outer gate save failure does not publish Warp or approach")
 b.save_path=""
 b.automation.position_changed(300,Vector2i(108,226))
 check(not b.handle({"type":"quest_talk","npc_id":inside.id}).get("ok",false),"failed outer gate cannot authorize project inner-gate arrival")
 check(FinalRoute.entry(b),"actual outer gate, twelve-cell pocket and original cave gate")
 check(b.quest_arrival.has_arrival(b,32001,Vector2i(29,3)) and not b.quest_arrival.has_stage(b,FIRST),"entry grants route but never first battle stage")
 check(b.handle({"type":"report_position","map_id":300,"cell":[108,225]}).get("ok",false),"original entry portal returns to NPC entity landing")
 check(b.handle({"type":"report_position","map_id":300,"cell":[108,226]}).get("ok",false),"legitimate original entity landing may step off")
 check(FinalRoute.commit(b,"genout/wpm_300_108_225"),"original return pocket permits legal reentry without project move")
 check(FinalRoute.near(b,"300/sb_skr.arg",range(32001,32011)),"original alternative portals and floors reach first Boss")
 actual_guard(b,"300/sb_skr.arg",FIRST)
 check(FinalRoute.near(b,"genout/wpm_32016_31_39",range(32011,32017)),"first stage survives actual original cross-floor route")
 check(b.quest_arrival.has_stage(b,FIRST) and FinalRoute.commit(b,"genout/wpm_32016_31_39"),"source middle gate accepts four ENDs without END53 or four history items")
 check(FinalRoute.near(b,"300/sb_skt.arg",range(32016,32021)),"original later floors reach terminal Boss")
 actual_guard(b,"300/sb_skt.arg",LAST)
 var king:Dictionary=FinalRoute.npc(b,"777/ten.arg")
 check(not b.quest_arrival.check_action(b,king,{},"SERVICE").is_empty(),"terminal victory alone does not cross last original door")
 check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]),"walk terminal room to last original gate")
 await lan_last_gate(b)
 check(FinalRoute.near(b,"777/ten.arg",[32021]),"walk off original portal landing to king")
 var proof:Dictionary=b.quest_arrival.action_context(b,king,{},"SERVICE")
 check(not proof.is_empty() and b.quest_arrival.check_action_context(b,proof).is_empty(),"real two battles and last gate issue exact king service receipt")
 check(RouteDriver.walk(b,32021,Vector2i(32,47),[32021]).get("ok",false),"walk to actual final-room original exit")
 check(b.handle({"type":"report_position","map_id":32021,"cell":[31,53]}).get("ok",false),"actual source portal leaves king component")
 check(b.quest_arrival.has_stage(b,FIRST) and b.quest_arrival.has_stage(b,LAST) and not b.quest_arrival.check_action_context(b,proof).is_empty(),"same-scope exit keeps both battle stages but clears final receipt")
 check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(b,"genout/wpm_32021_31_51") and FinalRoute.near(b,"777/ten.arg",[32021]),"source final door can legally be crossed again")
 var renewed:Dictionary=b.quest_arrival.action_context(b,king,{},"SERVICE")
 check(not renewed.is_empty() and renewed.epoch==proof.epoch and renewed.marks!=proof.marks and not b.quest_arrival.check_action_context(b,proof).is_empty(),"final door reentry changes mark generation without reviving old preview")
 var path:String="user://transmigration-arrival-restart.json"
 check(b.session.save_game(path),"save real route profile without persisting arrival proof")
 b.automation.position_changed(32021,Vector2i(32,28))
 check(not b.quest_arrival.has_stage(b,FIRST) and not b.quest_arrival.has_stage(b,LAST) and not b.quest_arrival.check_action_context(b,renewed).is_empty(),"same-component project move clears both stages and final receipt")
 check(b.load_profile(path) and not b.quest_arrival.has_stage(b,FIRST) and not b.quest_arrival.check_action_context(b,renewed).is_empty(),"real load never restores proof from END flags or persisted room")
 var restored=final_backend()
 check(restored.load_profile(path) and not restored.quest_arrival.check_action_context(restored,renewed).is_empty(),"fresh backend cannot replay pre-restart receipt")
 restored.free()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 b.free()
 print("QUEST ARRIVAL TRANSMIGRATION: %d failures"%failures);quit(1 if failures else 0)
