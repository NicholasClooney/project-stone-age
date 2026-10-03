extends "res://tests/quest_arrival_transmigration_test.gd"
const Candidates=preload("res://tests/transmigration_candidate_test.gd")
const KING="777/ten.arg@32021:31:28"
func actual_guard(b,source:String,stage:String)->void:
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":FinalRoute.npc(b,source).id})
 check(opened.get("ok",false) and choose(b,opened,"yes").get("ok",false) and b.battle_open,"source guardian begins: "+source)
 if not b.battle_open:return
 var expected:Array=FinalRoute.npc(b,source).branches[0].guard.enemy_ids.map(func(value):return int(value))
 check(b.session._pending.enemies.map(func(enemy):return int(enemy.source_enemy_id))==expected,"exact source five/ten enemy order")
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://no-king-guard-parent/save.json"
 fight(b)
 check(b.session.snapshot()==before and not b.quest_arrival.has_stage(b,stage),"failed guard save retains profile and grants no stage")
 b.save_path="user://king-guards.json"
 check(b.handle({"type":"battle_close"}).get("ok",false) and FileAccess.file_exists(b.save_path),"real guard retry writes disk then closes")
 check(b.quest_arrival.has_stage(b,stage),"saved original guard Warp establishes private stage")
func run()->void:
 var b=final_backend()
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
 b.quest_catalog.reward_pets.merge(source.reward_pets,true)
 b.session._profile.pets=[Candidates.pet(693,1),Candidates.pet(6,2)]
 b.session._profile.next_pet_id=3;b.session._profile.active_pet=1
 var before:Dictionary=b.session.snapshot()
 b.automation.position_changed(32021,Vector2i(31,29))
 check(not b.handle({"type":"quest_talk","npc_id":KING}).ok and b.session.snapshot()==before,"project arrival never opens real king service")
 check(FinalRoute.entry(b),"real outer and cave gates")
 check(FinalRoute.near(b,"300/sb_skr.arg",range(32001,32011)),"real route to first source battle")
 actual_guard(b,"300/sb_skr.arg",FIRST)
 check(FinalRoute.near(b,"genout/wpm_32016_31_39",range(32011,32017)) and FinalRoute.commit(b,"genout/wpm_32016_31_39"),"real middle gate after first saved battle")
 check(FinalRoute.near(b,"300/sb_skt.arg",range(32016,32021)),"real route to final source battle")
 actual_guard(b,"300/sb_skt.arg",LAST)
 check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(b,"genout/wpm_32021_31_51") and FinalRoute.near(b,"777/ten.arg",[32021]),"real final gate and continuous walk to king")
 root.add_child(b)
 var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"king two-device server uses isolated ephemeral port")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);links.append(link);link.connect_now()
 check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"two devices connected")
 await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
 var first:Dictionary=await request(links[0],{"type":"quest_talk","npc_id":KING})
 check(first.get("ok",false) and first.has("transmigration") and not first.has("dialogue"),"quest_talk returns actual top-level preview")
 if not first.has("transmigration"):
  print("KING REJECTION: ",first)
  for link in links:link.close()
  server.stop();server.queue_free();b.queue_free();quit(1);return
 var second:Dictionary=await request(links[1],{"type":"transmigration","action":"preview","npc_id":KING,"pet_ids":["pet-1"]})
 check(second.has("transmigration") and second.transmigration.token!=first.transmigration.token,"new device preview supersedes old token")
 if not second.has("transmigration"):
  print("SECOND PREVIEW REJECTION: ",second);quit(1);return
 var current:String=second.transmigration.token
 check(not (await request(links[0],{"type":"transmigration","action":"cancel","token":first.transmigration.token})).ok and b.transmigration.pending.token==current,"late cancel cannot clear newer preview")
 check(not (await request(links[0],{"type":"transmigration","action":"confirm","token":first.transmigration.token})).ok,"old device cannot confirm replaced preview")
 before=b.session.snapshot()
 var frozen:Dictionary=b.transmigration.pending.candidate.duplicate(true)
 var proof:Dictionary=b.transmigration.pending.proof.duplicate(true)
 b.save_path="user://no-king-transaction-parent/save.json"
 for retry in range(2):
  var failed:Dictionary=await request(links[1],{"type":"transmigration","action":"confirm","token":current})
  check(failed.get("reason")=="save_failed" and b.session.snapshot()==before and b.transmigration.pending.candidate==frozen and b.quest_arrival.check_action_context(b,proof).is_empty(),"failed save keeps complete original state/proof/seed for retry %d"%retry)
 b.save_path="user://king-transaction.json"
 var success:Dictionary=await request(links[1],{"type":"transmigration","action":"confirm","token":current})
 check(success.ok and success.get("closed",false) and success.transaction_id==current,"real king confirms exactly one atomic transaction")
 var after:Dictionary=b.session.snapshot()
 for key in after:
  if after[key]!=frozen.get(key):print("POST-SAVE DIFF ",key," frozen=",frozen.get(key)," actual=",after[key])
 check(after==frozen and after.player.transmigration==1 and after.location=={"map_id":1006,"x":15,"y":22},"all authoritative fields equal frozen candidate including village")
 check(b.transmigration.pending.is_empty() and not b.quest_arrival.check_action_context(b,proof).is_empty(),"only successful save consumes arrival and pending")
 check(not (await request(links[0],{"type":"transmigration","action":"confirm","token":current})).ok and b.session.snapshot()==after,"second-device ACK replay never duplicates reward")
 var restored=Backend.new()
 var loaded:bool=restored.load_profile(b.save_path)
 var readback:Dictionary=restored.session.snapshot()
 # The genuine loader normalizes JSON integer-valued floats recursively.
 # Compare every value after that same numeric representation conversion.
 var disk_expected:Dictionary=restored.session._normalize_numbers(after)
 for key in after:
  if disk_expected[key]!=readback.get(key):print("READBACK DIFF ",key," saved=",after[key]," actual=",readback.get(key))
 check(loaded and readback==disk_expected,"new server instance reads exact committed village/reward/history")
 check(not restored.handle({"type":"transmigration","action":"confirm","token":current}).ok,"restart cannot reuse old token")
 restored.free()
 for link in links:link.close()
 links=[];server.stop();server.queue_free();b.queue_free()
 for filename in ["king-transaction.json","king-guards.json"]:
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://"+filename+suffix))
 print("TRANSMIGRATION SERVICE: %d failures"%failures)
 quit(1 if failures else 0)
