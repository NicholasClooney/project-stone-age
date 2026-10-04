extends "res://tests/quest_auto_public_corridors_execution_test.gd"
## Separate deterministic original-encounter proof, not a natural-rate benchmark.
## Strong stats and initial village position are inherited explicit fixtures.
## Random encounters are suppressed ONLY during the actual request/village exit
## and after the first-hit assertion while testing real saved battle continuation.
func run()->void:
 deadline=Time.get_ticks_msec()+55000
 var b=fixture("C")
 var packets:Array=listen(b)
 if not await prepare(b,packets):b.free();quit(1);return
 var npc:Dictionary=b.original_quests.npc_by_id(str(b.quest_auto.step.npc_id))
 var proposal:Dictionary=Navigation.new().next_segment(b,npc,"C",3)
 if not check(proposal.get("audit_id","")==AUDIT_ID and proposal.get("kind","")=="public_stride" and proposal.get("points",[]).size()==3,"Actual job12 proposes a three-cell stride on the NEW corridor"):
  b.free();quit(1);return
 var oracle=preload("res://server/encounter_catalog.gd").new()
 var rng:=RandomNumberGenerator.new()
 var chosen:=-1
 for seed_value in range(1,1001):
  rng.seed=seed_value
  oracle.pressure=b.encounter_catalog.pressure
  var first_hit:=-1
  for index in range(3):
   var point:Dictionary=proposal.points[index]
   if oracle.step(int(point.map_id),Vector2i(point.cell[0],point.cell[1]),rng):first_hit=index;break
  if first_hit==1:chosen=seed_value;break
 if not check(chosen>=0,"Independent original catalog oracle finds a deterministic SECOND-cell first hit"):
  b.free();quit(1);return
 b.encounter_rng.seed=chosen
 b.session._profile.no_random_encounters=false
 b.field_cells.clear()
 packets.clear()
 var ticks:=0
 while b.quest_auto.running and b.quest_auto.phase!="battle" and in_time():
  b.quest_auto.tick(b,0.05)
  # Three-cell segment has no complete ACK before its second-cell encounter.
  ticks+=1
  if ticks%100==0:await process_frame
 var first:Dictionary=proposal.points[0]
 var hit:Dictionary=proposal.points[1]
 var hit_cell:=Vector2i(hit.cell[0],hit.cell[1])
 check(b.quest_auto.phase=="battle" and b.battle_open and b.quest_auto.owns_battle and b.automation.compact_active,"Original field_step opens existing ordinary attack plus compact battle")
 check(b.field_cells==[[100,first.cell[0],first.cell[1]],[100,hit.cell[0],hit.cell[1]]],"Actual field_step rolls only first and second logical cells; third cell never executes")
 check(b.automation.position_cell==hit_cell,"Authority stops at the actual first-hit second cell")
 var old:Dictionary=packets[-1].duplicate(true) if not packets.is_empty() else {}
 if check(not old.is_empty(),"Actual committed prefix was published before encounter"):
  acknowledge(b,old)
 b.quest_auto.tick(b,10.0)
 check(b.field_cells.size()==2 and b.automation.position_cell==hit_cell,"Late prefix ACK and large delta cannot revive discarded third cell")
 var resumed:=false
 # Separate continuation check: disable subsequent random encounters, never
 # force outcome, alter battle RNG or bypass ordinary battle save transaction.
 b.session._profile.no_random_encounters=true
 ticks=0
 while b.quest_auto.running and not resumed and in_time():
  b.automation.tick(1.0)
  b.quest_auto.tick(b,0.1)
  resumed=b.field_cells.size()>2
  ticks+=1
  if ticks%100==0:await process_frame
 check(resumed and not b.battle_open and not b.session._profile.completed_battles.is_empty(),"Real ordinary battle victory saves and replans from the actual hit cell")
 if resumed and not old.is_empty() and not packets.is_empty():
  check(packets[-1].quest_segment_id!=old.quest_segment_id,"Post-battle movement has a fresh segment identity")
 var position:Vector2i=b.automation.position_cell
 var calls:int=b.field_cells.size()
 b.handle({"type":"quest_auto_stop"})
 if not old.is_empty():acknowledge(b,old)
 b.quest_auto.tick(b,10.0)
 check(not b.quest_auto.running and b.automation.position_cell==position and b.field_cells.size()==calls,"Cancellation and stale ACK cannot resurrect old movement")
 persisted(b,"encounter")
 b.free()
 check(in_time(),"Encounter condition deadline not exceeded")
 print("QUEST AUTO PUBLIC CORRIDORS ENCOUNTER: %d assertions, %d failures; oracle_seed=%d wall_ms=%d"%[assertions,failures,chosen,Time.get_ticks_msec()-suite_started])
 quit(1 if failures else 0)
