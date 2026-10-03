extends "res://tests/transmigration_service_test.gd"
func run()->void:
 var b=final_backend()
 # Genuine old schema: known positive count, no v7 group or invented equation.
 var old:Dictionary=b.session.snapshot();old.version=6;old.erase("rebirth");old.player.transmigration=3
 var path:="user://king-unknown-legacy.json"
 var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
 check(b.load_profile(path) and b.session.snapshot().rebirth.history=="legacy_unknown","actual old positive history loads without invented Q/L")
 check(FinalRoute.entry(b) and FinalRoute.near(b,"300/sb_skr.arg",range(32001,32011)),"unknown-history character can play original gates and route")
 actual_guard(b,"300/sb_skr.arg",FIRST)
 check(FinalRoute.near(b,"genout/wpm_32016_31_39",range(32011,32017)) and FinalRoute.commit(b,"genout/wpm_32016_31_39") and FinalRoute.near(b,"300/sb_skt.arg",range(32016,32021)),"unknown history does not block ordinary mid-route play")
 actual_guard(b,"300/sb_skt.arg",LAST)
 check(FinalRoute.near(b,"genout/wpm_32021_31_51",[32021]) and FinalRoute.commit(b,"genout/wpm_32021_31_51") and FinalRoute.near(b,"777/ten.arg",[32021]),"old character genuinely completes final route and room gate")
 var before:Dictionary=b.session.snapshot()
 var npc:Dictionary=FinalRoute.npc(b,"777/ten.arg")
 check(b.quest_arrival.check_action(b,npc,{},"SERVICE").is_empty(),"unknown-history rejection is not missing arrival")
 for command in [{"type":"quest_talk","npc_id":KING},{"type":"transmigration","action":"preview","npc_id":KING,"pet_ids":[]}]:
  var reply:Dictionary=b.handle(command)
  check(not reply.ok and str(reply.reason).contains("历史缺失") and b.session.snapshot()==before and b.transmigration.pending.is_empty(),"real king rejects only unknown inheritance while preserving assets")
 b.free()
 for filename in ["king-unknown-legacy.json","king-guards.json"]:
  for suffix in ["",".tmp",".bak"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://"+filename+suffix))
 print("TRANSMIGRATION UNKNOWN SERVICE: %d failures"%failures);quit(1 if failures else 0)
