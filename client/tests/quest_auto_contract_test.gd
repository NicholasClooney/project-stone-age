extends SceneTree
const Backend=preload("res://server/backend.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const State=preload("res://server/quest_auto_state.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 check(Settings.effective({}).quest=={"mode":"A","loot_minutes":30},"Old profiles default to A and 30 minutes")
 for value in [0,-1,181,1.2,INF,NAN,"30",true]:
  check(not Settings.apply_patch({},{"quest":{"loot_minutes":value}}).ok,"Reject invalid budget "+str(value))
 for value in ["a","legacy",1,true]:
  check(not Settings.apply_patch({},{"quest":{"mode":value}}).ok,"Reject invalid mode")
 var b=Backend.new()
 var reply:Dictionary=b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"C","loot_minutes":180}}})
 check(reply.ok and Settings.effective(b.session.automation_settings()).quest.mode=="C","Real command saves quest preferences")
 b.save_path="user://missing-quest-contract-directory/profile.json"
 var before:Dictionary=b.session.snapshot()
 reply=b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"B"}}})
 check(not reply.ok and b.session.snapshot()==before,"Save failure rolls settings back")
 b.save_path="user://quest-auto-contract.json"
 check(b.save(),"Save real profile")
 var c=Backend.new()
 check(c.load_profile(b.save_path),"Load real profile")
 check(Settings.effective(c.session.automation_settings()).quest=={"mode":"C","loot_minutes":180},"Settings persist without save format change")
 for legacy_version in [1,2]:
  c.quest_auto.load_resume(c,{"version":legacy_version,"quest_id":11,"strict_walk":false})
  check(c.quest_auto.strict_walk and c.quest_auto.snapshot(c).effective_mode=="A","Legacy resume never restores convenience movement")
  c.quest_auto.stop(c)
 b.quest_auto.stop(b)
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(1000,Vector2i(56,58))
 reply=b.handle({"type":"quest_auto_start","quest_id":11,"strict_walk":false,"client":"test"})
 check(reply.ok and b.quest_auto.strict_walk,"Client cannot request legacy convenience under mode A")
 var origin:Vector2i=b.automation.position_cell
 b.quest_auto.tick(b,0.21)
 check(b.automation.position_map==1000 and (b.automation.position_cell-origin).length()<=1.0,"Default A cannot jump to far shell NPC")
 check(b.quest_auto.snapshot(b).available_modes==["A","B","C"] and b.quest_auto.snapshot(b).settings.mode=="C","Accepted requested C stays explicit, with protected segments still walking")
 b.quest_auto.stop(b)
 var state=State.new()
 state.begin();state.select_step("reward:one");state.wait_for("reward","token","npc","character")
 var command={"quest_run_id":state.run_id,"quest_step_id":state.step_id,"quest_revision":state.revision,"token":"token"}
 check(state.matches(command,"character"),"Matching capability accepted")
 check(not state.matches(command,"other"),"Other character rejected")
 var checkpoint:Dictionary=state.checkpoint()
 check(not checkpoint.has("waiting") and not checkpoint.has("token"),"Checkpoint excludes pending capability")
 state.invalidate()
 check(not state.matches(command,"character"),"Cancellation invalidates late token")
 check(state.restore(checkpoint) and state.waiting.is_empty() and state.revision>int(command.quest_revision),"Restart rotates revision and strips token")
 var previous:String=state.run_id
 state.begin()
 check(state.run_id!=previous,"New run cannot reuse capability")
 for invalid in [{},{"run_id":previous,"step_id":"x","revision":NAN},{"run_id":previous,"step_id":"x","revision":-1}]:
  check(not state.restore(invalid),"Malformed checkpoint rejected")
 for file in [b.save_path,b.save_path+".bak",b.save_path+".tmp"]:
  if FileAccess.file_exists(file):DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
 b.free();c.free()
 print("QUEST AUTO CONTRACT: %d failures"%failures)
 quit(1 if failures else 0)
