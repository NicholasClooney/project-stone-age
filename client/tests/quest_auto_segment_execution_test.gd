extends SceneTree
const RealBackend=preload("res://server/backend.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Encounters=preload("res://server/encounter_catalog.gd")
class Backend extends "res://server/backend.gd":
 var cells:Array=[]
 func _cmd_field_step(command:Dictionary)->Dictionary:
  cells.append({"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]})
  return super._cmd_field_step(command)
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func setup(mode:String):
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.session._profile.no_random_encounters=true
 b.session._profile.original_savepoint_bits=2
 b.automation.position_changed(100,Vector2i(637,494))
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).ok,"Save selected mode")
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"test","_quest_connection":17}).ok,"Start real shell route")
 return b
func ack(b)->Dictionary:
 if b.quest_auto.issued.is_empty():return {}
 var p:Dictionary=b.quest_auto.issued[-1]
 return {"type":"report_position","client":"test","_quest_connection":17,"map_id":p.map_id,"cell":p.cell.duplicate(),"quest_position_seq":p.seq,"quest_run_id":p.quest_run_id,"quest_step_id":p.quest_step_id,"quest_revision":p.quest_revision,"quest_segment_id":p.quest_segment_id}
func run()->void:
 var sequences:Dictionary={}
 for mode in ["A","B","C"]:
  var b=setup(mode)
  var npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
  var expected:Array=Navigation.new().plan(b,npc)
  var walked:Array=[]
  var fast_packets:=[0]
  b.event.connect(func(event):
   if event.get("type")=="position" and event.get("quest_segment",{}).get("kind") in ["public_stride","public_jump"]:
    fast_packets[0]+=1
    var prefix:Array=event.quest_segment.cells
    check(prefix.size()<=3 and prefix[-1].cell==event.cell,"Actual packet contains only current committed prefix")
    check(not event.quest_segment.has("navigation_key") and not event.quest_segment.has("remaining"),"No local proposal fields published")
  )
  for index in range(2000):
   if b.automation.position_map!=100 or not b.quest_auto.running:break
   var old:Vector2i=b.automation.position_cell
   b.quest_auto.tick(b,1.0)
   var cell:Vector2i=b.automation.position_cell
   if old!=cell or b.automation.position_map!=100:
    walked.append({"map_id":b.automation.position_map,"cell":[cell.x,cell.y]})
    if mode!="B" and b.automation.position_map==100:check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"Large tick executes at most one actual logical cell")
   if b.quest_auto.phase=="segment_landing":
    var count:int=b.cells.size();var position:Vector2i=b.automation.position_cell
    b.quest_auto.tick(b,1.0)
    check(b.cells.size()==count and b.automation.position_cell==position,"Segment endpoint blocks until exact ACK")
    b.handle(ack(b))
  check(b.automation.position_map==2000,"Actual mode reaches original portal: "+mode+" "+b.quest_auto.message)
  var expected_cells:Array=expected.map(func(p):return {"map_id":int(p.map_id),"cell":[int(p.cell[0]),int(p.cell[1])]})
  if mode in ["A","C"]:check(walked==expected_cells,"Actual "+mode+" follows complete original A path")
  if mode=="B":check(walked.size()==3 and walked[0]==expected_cells[-3],"B ends before original portal and walks final two points")
  check(fast_packets[0]>0 if mode!="A" else fast_packets[0]==0,"Fast mode actually exercised only audited geometry")
  sequences[mode]=walked
  b.free()
 check(sequences.A==sequences.C,"A and C full authority sequences are identical")
 cadence_and_ack()
 encounters()
 cancellation()
 print("QUEST AUTO SEGMENT EXECUTION: %d failures"%failures)
 quit(1 if failures else 0)
func cadence_and_ack()->void:
 var b=setup("C")
 var origin:Vector2i=b.automation.position_cell
 b.quest_auto.tick(b,0.05)
 check(b.automation.position_cell==origin,"C waits for 0.1 seconds")
 b.quest_auto.tick(b,0.05)
 check(b.cells.size()==1,"C advances first cell at twice original cadence")
 b.quest_auto.tick(b,0.1);b.quest_auto.tick(b,0.1)
 check(b.cells.size()==3 and b.quest_auto.phase=="segment_landing","C stops after exactly three cells")
 var current:Dictionary=ack(b)
 var legacy:Dictionary=current.duplicate()
 for key in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:legacy.erase(key)
 b.handle(legacy)
 check(b.quest_auto.phase=="segment_landing","Real C endpoint rejects seq-only ACK")
 for key in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq","map_id","cell","client","_quest_connection"]:
  var wrong:Dictionary=current.duplicate(true)
  wrong[key]=[1,1] if key=="cell" else -1 if key in ["quest_revision","quest_position_seq","map_id","_quest_connection"] else "stale"
  b.handle(wrong)
  check(b.quest_auto.phase=="segment_landing" and b.quest_auto.running,"Wrong endpoint capability rejected: "+key)
 var position:Vector2i=b.automation.position_cell
 b.handle({"type":"report_position","map_id":100,"cell":[position.x,position.y],"client":"test","_quest_connection":17})
 check(b.quest_auto.phase=="segment_landing","Untagged same-cell report does not release fast endpoint")
 b.quest_auto.detach(b,17)
 b.quest_auto.tick(b,10.0)
 b.handle(current)
 check(b.quest_auto.detached and b.quest_auto.issued.is_empty(),"Detached old ACK cannot restore tail")
 b.handle({"type":"report_position","map_id":100,"cell":[position.x,position.y],"client":"return","_quest_connection":22})
 check(not b.quest_auto.detached and b.quest_auto.phase=="segment_landing","Reconnect binds but waits for newly issued endpoint")
 var fresh:Dictionary=ack(b);fresh.client="return";fresh._quest_connection=22
 b.handle(current)
 check(b.quest_auto.phase=="segment_landing","Old device cannot acknowledge reissued endpoint")
 b.handle(fresh)
 check(b.quest_auto.phase=="travel","Fresh full reconnect ACK releases endpoint")
 b.quest_auto.tick(b,0.1)
 check(not b.quest_auto.segment.proposal.is_empty(),"New segment staged after reconnect")
 var saved:Dictionary=b.quest_auto.segment.proposal.duplicate(true)
 b.save_path="user://segment-settings-missing-parent/file.json"
 check(not b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"B"}}}).ok and b.quest_auto.segment.proposal==saved,"Failed settings save preserves current segment")
 b.save_path=""
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"A"}}}).ok and b.quest_auto.segment.proposal.is_empty(),"Saved mode change invalidates remaining tail")
 position=b.automation.position_cell
 b.quest_auto.tick(b,0.1)
 check(b.automation.position_cell==position,"A waits full original cadence after mode switch")
 b.quest_auto.tick(b,0.1)
 check((b.automation.position_cell-position).length()==1.0 and b.quest_auto.execution_mode=="A","Switch replans A from last authoritative cell")
 b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"C"}}})
 b.quest_auto.tick(b,0.1)
 var before_version:int=b.quest_auto.position_serial
 b.session._profile.player.level+=1
 b.quest_auto.tick(b,0.1)
 check(b.quest_auto.running and b.quest_auto.position_serial==before_version+1,"Real navigation eligibility change discards tail and safely replans one cell")
 while b.quest_auto.phase=="travel" and b.quest_auto.running:b.quest_auto.tick(b,0.1)
 var stale:Dictionary=ack(b);stale.client="return";stale._quest_connection=22
 b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"B"}}})
 b.handle(stale)
 check(b.quest_auto.phase=="segment_landing","Settings change at endpoint preserves wait and rejects prior revision")
 var replacement:Dictionary=ack(b);replacement.client="return";replacement._quest_connection=22
 b.handle(replacement)
 check(b.quest_auto.phase=="travel","Replacement endpoint capability releases mode-change wait")
 b.free()
func encounters()->void:
 var b=setup("C")
 var nav=Navigation.new()
 var npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
 var points:Array=nav.next_segment(b,npc,"C",3).points
 var chosen:=-1
 for seed_value in range(10000):
  var rng=RandomNumberGenerator.new();rng.seed=seed_value
  var source=Encounters.new(b.encounter_catalog.data)
  var hit:=-1
  for index in range(3):
   if source.step(100,Vector2i(points[index].cell[0],points[index].cell[1]),rng):hit=index;break
  if hit==1:chosen=seed_value;break
 check(chosen>=0,"Find seed with original encounter on second real C cell")
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.encounter_rng.seed=chosen
 b.session._profile.no_random_encounters=false
 b.quest_auto.tick(b,0.1);b.quest_auto.tick(b,0.1)
 check(b.cells.size()==2 and b.quest_auto.phase=="battle" and b.quest_auto.owns_battle and b.automation.compact_active,"Original second-cell encounter truncates C and takes ordinary compact attack")
 check(b.automation.position_cell==Vector2i(points[1].cell[0],points[1].cell[1]) and b.quest_auto.segment.proposal.is_empty(),"First encounter leaves authority exactly on hit cell without tail")
 b.quest_auto.tick(b,100.0)
 check(b.cells.size()==2,"Battle never rolls or moves unexecuted tail")
 var battle_id:String=b.session._pending.battle_id
 var serial:int=b.quest_save_serial
 b.session._profile.no_random_encounters=true
 for index in range(100):
  if not b.automation.running:break
  b.automation.tick(1.0)
 # Replanning may conservatively use A if the new shortest suffix is unaudited.
 b.quest_auto.tick(b,0.2)
 check(b.quest_auto.running and b.quest_auto.phase=="travel" and battle_id in b.session._profile.completed_battles and b.quest_save_serial>serial,"Actual compact victory saves before automatically replanning C")
 check(b.cells.size()==3,"Victory resumes with one new original field step, not the old tail batch: "+str(b.cells)+" / "+b.quest_auto.message)
 b.quest_auto.stop(b);b.free()
func cancellation()->void:
 var b=setup("C")
 b.event.connect(func(event):
  if event.get("type")=="position" and event.has("quest_position_seq"):b.quest_auto.stop(b,"cancel during prefix")
 )
 b.quest_auto.tick(b,0.1)
 check(not b.quest_auto.running and b.cells.is_empty() and b.quest_auto.segment.proposal.is_empty(),"Synchronous prefix cancellation prevents later encounter and tail")
 b.free()
