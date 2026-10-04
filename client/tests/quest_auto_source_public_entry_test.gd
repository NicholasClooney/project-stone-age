extends "res://tests/quest_auto_source_dispatch_test.gd"
## Repeatable public admission/gate test, not natural-route or terminal proof.
## Trusted connection IDs below model the transport injection. UI owns real WS
## button acceptance. Random encounters are disabled explicitly in this fixture.
const Rules=preload("res://server/original_quests.gd")
const Policy=preload("res://scripts/quest_auto_policy.gd")
func entry_command()->Dictionary:
 return {"type":"quest_auto_start","quest_id":2,"client":"public-entry","_quest_connection":71}
func state(b)->Dictionary:
 return {"profile":b.session.snapshot(),"identity":b.quest_auto.identity.checkpoint(),"running":b.quest_auto.running,"phase":b.quest_auto.phase,"position":[b.automation.position_map,b.automation.position_cell],"serial":b.quest_save_serial,"pending":b.original_quests.pending.duplicate(true),"npc_version":b.original_quests.npc_state.version}
func setup_band(b,level:int)->void:
 b.session._profile.player.level=level
 b.session._profile.original_items.clear();b.session._profile.original_instances.clear()
 Equipment.add(b.session._profile,2757 if level>=70 else (2756 if level>=50 else 2755))
 b.automation.position_changed(851 if level>=70 else 811,Vector2i(29 if level>=70 else (28 if level>=50 else 30),22),true)
func rejected(b,command:Dictionary,label:String)->void:
 var before:=state(b)
 check(not b.handle(command).get("ok",false),label)
 check(state(b)==before,"Rejected start unchanged: "+label)
func admission_matrix()->void:
 var b=fresh();b.session._profile.no_random_encounters=true
 for level in [30,49,50,69,70]:
  setup_band(b,level)
  var before:=state(b)
  var view:Dictionary=b.quest_auto.snapshot(b).source_entry
  check(view=={"job_id":2,"enabled":true,"can_start":true,"reason":"","effective_mode":"A"},"Exact minimal authority projection at level "+str(level))
  check(b.quest_auto.snapshot(b).source_entry==view and state(b)==before,"Repeated projection is gameplay read-only")
  check(b.handle(entry_command()).ok,"Public start boundary level "+str(level))
  check(b.session.snapshot()==before.profile and b.quest_save_serial==before.serial and [b.automation.position_map,b.automation.position_cell]==before.position,"Admission never pays/saves/moves")
  b.quest_auto.stop(b)
 for kind in ["level","ticket","lobby","protected","ended","disabled","client","connection","fractional_connection","battle","pending","party","job35","job34"]:
  setup_band(b,35)
  var command:=entry_command()
  var events:Array=b.quest_catalog.enabled_events.duplicate()
  match kind:
   "level":b.session._profile.player.level=29
   "ticket":b.session._profile.original_items.clear();b.session._profile.original_instances.clear()
   "lobby":b.automation.position_changed(851,Vector2i(29,22),true)
   "protected":b.automation.position_changed(800,Vector2i(29,21),true,"project")
   "ended":Rules.set_flag(b.session._profile,"ended",44,true)
   "disabled":b.quest_catalog.enabled_events.erase(44)
   "client":command.erase("client")
   "connection":command.erase("_quest_connection")
   "fractional_connection":command._quest_connection=71.5
   "battle":b.battle_open=true
   "pending":b.original_quests.pending={"token":"fixture-manual"}
   "party":b.quest_visit_guard=func():return "fixture party"
   "job35":command.quest_id=35
   "job34":command.quest_id=34
  rejected(b,command,kind)
  if kind not in ["client","connection","fractional_connection","job35","job34"]:
   var before:=state(b)
   var denied:Dictionary=b.quest_auto.snapshot(b).source_entry
   check(not denied.can_start and not denied.reason.is_empty(),"Authority explains ineligibility: "+kind)
   check(state(b)==before,"Ineligible projection has no side effect: "+kind)
  b.quest_catalog.enabled_events.assign(events)
  Rules.set_flag(b.session._profile,"ended",44,false)
  b.battle_open=false;b.original_quests.pending={};b.quest_visit_guard=Callable()
 check(Policy.supports(2,44) and not Policy.supports(2,34) and not Policy.supports(35,35) and not Policy.supports(34,34),"Only exact public job/event pair added")
 b.free()
func bands_and_modes()->void:
 for level in [35,55,75]:
  var b=fresh();b.session._profile.no_random_encounters=true
  setup_band(b,level)
  var preference:String="A" if level==35 else ("B" if level==55 else "C")
  b.session._profile.automation_settings={"quest":{"mode":preference}}
  b.save_path="user://source-public-entry-%d.json"%level
  check(b.save(),"Real saved public baseline")
  var disk:=FileAccess.get_file_as_string(b.save_path)
  check(b.handle(entry_command()).ok,"Public representative start "+str(level))
  check(FileAccess.get_file_as_string(b.save_path)==disk,"Start itself has no disk write")
  var view:Dictionary=b.quest_auto.snapshot(b)
  check(view.effective_mode=="A" and view.available_modes==["A"] and view.settings.mode==preference,"Stored preference preserved; source executes A")
  tick(b)
  check(b.quest_auto.phase=="source_dialogue" and b.quest_auto.source_frame!=null,"Real gate confirmation opens on first public tick")
  if b.quest_auto.source_frame==null:b.free();continue
  var frame=b.quest_auto.source_frame
  var identity:Dictionary=b.quest_auto.identity.checkpoint()
  var token:String=b.original_quests.pending.token
  for mode in ["B","C","A"]:
   check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).ok,"Legal setting saves while original source page remains open")
   check(b.quest_auto.identity.checkpoint()==identity and b.quest_auto.source_frame==frame and b.original_quests.pending.token==token,"Preference cannot rotate source identity/page")
  var settings:Dictionary=b.session.automation_settings().duplicate(true)
  var saved_disk:=FileAccess.get_file_as_string(b.save_path)
  DirAccess.make_dir_absolute(b.save_path+".tmp")
  var failed:Dictionary=b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"C"}}})
  check(not failed.ok and failed.reason=="save_failed","Actual tmp settings write failure rejected")
  check(b.session.automation_settings()==settings and FileAccess.get_file_as_string(b.save_path)==saved_disk and b.quest_auto.identity.checkpoint()==identity and b.original_quests.pending.token==token,"Save failure rolls back settings and retains original page")
  DirAccess.remove_absolute(b.save_path+".tmp")
  tick(b)
  var base:=840 if level>=70 else (820 if level>=50 else 800)
  check(b.automation.position_map==base and b.quest_auto.phase=="landing","Original gate transaction reaches correct floor")
  check(b.quest_arrival.has_arrival(b,base,b.automation.position_cell),"Actual original gate grants arrival")
  check(not (2757 if level>=70 else (2756 if level>=50 else 2755)) in b.session._profile.original_items,"Original gate consumes entry ticket once")
  var packet:=ack(b)
  check(not packet.is_empty() and b.handle(packet).ok and b.quest_auto.phase=="travel","Full issued gate identity ACK permits continuation")
  identity=b.quest_auto.identity.checkpoint()
  var receipt:Dictionary=b.quest_auto.motion.duplicate(true)
  check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"B"}}}).ok,"Travel preference update succeeds")
  check(b.quest_auto.identity.checkpoint()==identity and b.quest_auto.motion==receipt,"Travel preference cannot revoke source receipt")
  b.handle({"type":"quest_auto_stop"})
  var stopped:=state(b)
  b.handle(packet);tick(b)
  check(state(b)==stopped and not b.quest_auto.running,"Stopped old receipt/tick cannot move/pay/resume")
  b.free()
func run()->void:
 admission_matrix()
 bands_and_modes()
 print("QUEST AUTO SOURCE PUBLIC ENTRY: %d assertions, %d failures; explicit no_random_encounters; NO full-route claim"%[assertions,failures])
 quit(1 if failures else 0)
