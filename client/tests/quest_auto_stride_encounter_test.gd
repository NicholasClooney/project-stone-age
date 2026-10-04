extends SceneTree
const Rules=preload("res://server/original_quests.gd")
class ObservedBackend extends "res://server/backend.gd":
 var field_cells:Array=[]
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_cells.append([int(command.map_id),int(command.cell[0]),int(command.cell[1])])
  return super._cmd_field_step(command)
var failures:=0
func check(value:bool,label:String)->bool:
 if not value:failures+=1;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func acknowledge(b,packet:Dictionary)->void:
 var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":"test","_quest_connection":17}
 for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:command[field]=packet[field]
 b.handle(command)
func run()->void:
 var b=ObservedBackend.new()
 b.quest_catalog.enabled_events=[2]
 b.session._profile.no_random_encounters=true
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.automation.position_changed(1000,Vector2i(89,73))
 b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":"C"}}})
 if not b.quest_auto.snapshot(b).available_modes.has("C"):
  check(false,"C executor must be integrated before this acceptance suite")
  b.free();quit(1);return
 var packets:Array=[]
 b.event.connect(func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_segment_id"):packets.append(event.duplicate(true))
 )
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"test","_quest_connection":17}).ok,"Real shell request starts before public travel")
 var acknowledged:=0
 for index in range(5000):
  if b.automation.position_map==100:break
  b.quest_auto.tick(b,0.21)
  while acknowledged<packets.size():
   var packet:Dictionary=packets[acknowledged];acknowledged+=1
   if packet.quest_ack_required:acknowledge(b,packet)
 check(b.automation.position_map==100 and Rules.flag(b.session._profile,"now",2),"Original request and village exit actually complete")
 var npc:Dictionary=b.original_quests.npc_by_id(str(b.quest_auto.step.npc_id))
 var nav=preload("res://server/quest_auto_navigation.gd").new()
 var proposal:Dictionary=nav.next_segment(b,npc,"C",3)
 if not check(proposal.get("kind")=="public_stride" and proposal.points.size()==3,"Reviewed original corridor has a full three-cell stride"):
  b.free();quit(1);return
 # Find a deterministic original RNG seed whose first hit is the second cell.
 # The oracle rolls the real area pressure, never forces or stubs an encounter.
 var oracle=preload("res://server/encounter_catalog.gd").new()
 var rng:=RandomNumberGenerator.new()
 var chosen:=-1
 for seed_value in range(1,1001):
  rng.seed=seed_value;oracle.pressure=b.encounter_catalog.pressure
  var first_hit:=-1
  for index in range(3):
   var point:Dictionary=proposal.points[index]
   if oracle.step(int(point.map_id),Vector2i(point.cell[0],point.cell[1]),rng):first_hit=index;break
  if first_hit==1:chosen=seed_value;break
 check(chosen>=0,"Original RNG produces a real middle-cell first encounter")
 b.encounter_rng.seed=chosen
 b.session._profile.no_random_encounters=false
 b.field_cells.clear();packets.clear();acknowledged=0
 for index in range(100):
  if b.quest_auto.phase=="battle":break
  b.quest_auto.tick(b,0.1)
 var first:Dictionary=proposal.points[0]
 var hit:Dictionary=proposal.points[1]
 check(b.quest_auto.phase=="battle" and b.battle_open and b.quest_auto.owns_battle and b.automation.compact_active,"First real hit opens the existing ordinary attack/compact lifecycle")
 check(b.field_cells==[[100,first.cell[0],first.cell[1]],[100,hit.cell[0],hit.cell[1]]],"Only the first two logical cells roll original encounters; the tail never rolls")
 check(b.automation.position_cell==Vector2i(hit.cell[0],hit.cell[1]),"Authority stops exactly at the first-hit area cell")
 var old:Dictionary=packets[0].duplicate(true) if not packets.is_empty() else {}
 if not old.is_empty():acknowledge(b,old)
 b.quest_auto.tick(b,10.0)
 check(b.field_cells.size()==2 and b.automation.position_cell==Vector2i(hit.cell[0],hit.cell[1]),"Late prefix ACK and large delta cannot execute the discarded battle tail")
 var resumed:=false
 b.session._profile.no_random_encounters=true
 for index in range(500):
  b.automation.tick(1.0)
  b.quest_auto.tick(b,0.1)
  if b.field_cells.size()>2:resumed=true;break
 check(resumed and not b.battle_open and not b.session._profile.completed_battles.is_empty(),"Actual saved ordinary victory replans and resumes from the hit cell")
 if resumed and not old.is_empty() and not packets.is_empty():check(packets[-1].quest_segment_id!=old.quest_segment_id,"Post-battle motion has a fresh segment identity")
 var position:Vector2i=b.automation.position_cell
 b.handle({"type":"quest_auto_stop"})
 if not old.is_empty():acknowledge(b,old)
 check(not b.quest_auto.running and b.automation.position_cell==position,"Cancelled old prefix cannot revive any remaining segment")
 b.free()
 print("QUEST AUTO STRIDE ENCOUNTER: %d failures"%failures)
 quit(1 if failures else 0)
