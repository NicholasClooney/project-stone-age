extends "res://tests/quest_auto_public_corridors_letters_test.gd"
## Incremental approach only: never complete the old adult/herb/shell chains.
const Motion=preload("res://server/quest_auto_motion.gd")
const CASES=[
 {"job":1,"label":"adult","start":[79,614],"sp_bits":1,"permit":true,"npc":"jaruga/event/event04_1","target_map":10204,"target_cell":[14,6]},
 {"job":11,"label":"shell-sp0","start":[259,171],"sp_bits":1,"permit":false,"npc":"sainasu/event/event02_2","target_map":1000,"target_cell":[57,124]},
 {"job":30,"label":"herb","start":[79,614],"sp_bits":1,"permit":true,"npc":"jaruga/event/event01_1","target_map":3110,"target_cell":[16,15]},
]
func approach_fixture(mode:String,spec:Dictionary):
 var b=CountedBackend.new()
 check(b.original_quests.npc_state.version==0 and b.original_quests.npc_state.records.is_empty() and b.original_quests.npc_state.spawn_attempts.is_empty(),"Fresh normal NPC birth state")
 b.original_quests.npc_state.spawn_rng.seed=1
 b.session._profile.player.level=140
 b.session._profile.player.base_stats={"vitality":12000,"strength":14000,"toughness":14000,"dexterity":3700}
 b.session._profile.player.allocated_stats={"vitality":111,"strength":133,"toughness":140,"dexterity":33}
 b.session._profile.player.stat_points=0
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.session._profile.no_random_encounters=true
 # Explicit birth SP0, not a change chosen after inspecting the selected route.
 b.session._profile.original_savepoint_bits=int(spec.sp_bits)
 # Explicit already-owned reusable travel permit for cross-island planning.
 # No purchase, original task flags/items, gate state or arrival proof injected.
 b.session._profile.travel_pass=bool(spec.permit)
 b.automation.position_changed(100,Vector2i(spec.start[0],spec.start[1]))
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).get("ok",false),"Persist actual mode "+mode)
 check(b.quest_auto.snapshot(b).available_modes.has(mode),"Actual mode available "+mode)
 var selected:Dictionary=b.quest_auto.strict_select(b,int(spec.job))
 var step:Dictionary=selected.get("step",{})
 # Imported coordinates are JSON integer-valued floats. Apply the same strict
 # finite/integer/range contract as receipts, never truncate fractional data.
 var target_checks:Dictionary={"status":selected.get("status")=="step","npc":step.get("npc_id")==spec.npc,"map":Motion.same_integer(step.get("map_id"),spec.target_map),"cell":Motion.cell(step.get("cell"))==spec.target_cell}
 check(target_checks.status and target_checks.npc and target_checks.map and target_checks.cell,"Original current target follows disclosed SP/prerequisites, not a forced test goal")
 print("LEGACY TARGET CHECKS ",JSON.stringify({"mode":mode,"job":spec.job,"checks":target_checks,"raw_array_equal":step.get("cell",[])==spec.target_cell}))
 print("LEGACY APPROACH INITIAL ",JSON.stringify({"mode":mode,"case":spec,"actual_selected":selected}))
 return b
func approach(b,mode:String,spec:Dictionary)->void:
 var started:int=Time.get_ticks_msec()
 var packets:Array=[]
 var observer:Callable=func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_segment_id"):
   packets.append({"packet":event.duplicate(true),"proposal":b.quest_auto.segment.proposal.duplicate(true)})
 b.event.connect(observer)
 # Inherited ACK helper uses this exact client/connection; no other owner acts.
 var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":int(spec.job),"client":"public-letters","_quest_connection":17})
 var accepted:bool=check(reply.get("ok",false),"Original legacy auto starts "+str(spec.label)+"/"+mode)
 var stats:Dictionary={"job":spec.job,"label":spec.label,"mode":mode,"new_audits":{},"old_audits":{},"fast_packets":0,"fast_segments":0,"field_calls":0,"protected_walk":0,"unaudited_walk":0,"door_walk":0,"portals":[],"simulated_seconds":0.0,"public100_simulated_seconds":0.0,"terminal":{},"stop_kind":""}
 var segment_ids:Dictionary={}
 var saw_undersea_portal:=false
 var reached:=false
 var ticks:=0
 var previous_was_door_walk:=false
 while accepted and b.quest_auto.running and not reached and Time.get_ticks_msec()<deadline:
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  b.quest_auto.tick(b,0.05)
  stats.simulated_seconds+=0.05
  if old_map==100:stats.public100_simulated_seconds+=0.05
  var map_id:int=b.automation.position_map
  var cell:Vector2i=b.automation.position_cell
  if map_id!=old_map or cell!=old:
   var packet:Dictionary=packets[-1].packet if not packets.is_empty() else {}
   var proposal:Dictionary=packets[-1].proposal if not packets.is_empty() else {}
   var kind:String=str(packet.get("quest_segment",{}).get("kind","walk"))
   var fast:bool=kind in ["public_jump","public_stride"]
   if fast:
    var audit_id:String=str(proposal.get("audit_id",""))
    var lane:Dictionary=reviewed_lane(audit_id)
    check(not lane.is_empty() and int(lane.map)==map_id and old_map==map_id,"Actual fast commit has exact reviewed lane, not map-only permission")
    check(not walk_protected(map_id,cell) and not b.quest_helper.places.links(map_id).has(cell),"Project destination is outside protected/portal cells")
    check(kind==("public_jump" if mode=="B" else "public_stride"),"Committed mode kind matches preference")
    if mode=="C":check(absi(cell.x-old.x)+absi(cell.y-old.y)==1 and packet.quest_segment.cells.size()<=3,"C stays adjacent with bounded prefix")
    stats.fast_packets+=1
    var group:Dictionary=stats.new_audits if Extra.LANES.any(func(lane_row):return lane_row.id==audit_id) else stats.old_audits
    if not group.has(audit_id):group[audit_id]={"packets":0,"segments":0}
    group[audit_id].packets+=1
    if not segment_ids.has(packet.quest_segment_id):
     segment_ids[packet.quest_segment_id]=true;stats.fast_segments+=1;group[audit_id].segments+=1
   elif map_id!=old_map:
    var portal:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
    check(not portal.is_empty() and int(portal.to_map)==map_id and Vector2i(portal.target[0],portal.target[1])==cell,"Original portal actually executes at the exact source and target")
    check(previous_was_door_walk,"Original portal is preceded by a separate real adjacent door step")
    stats.portals.append({"from_map":old_map,"from_cell":[old.x,old.y],"to_map":map_id,"cell":[cell.x,cell.y],"source":portal.get("source","")})
    if map_id==10201:
     check(old_map==1100 and old==Vector2i(96,62) and cell==Vector2i(6,4),"Original undersea entrance is exact, not project placement")
     saw_undersea_portal=true
   else:
    check(absi(cell.x-old.x)+absi(cell.y-old.y)==1,"Unaudited/protected movement remains original adjacent walk")
    if walk_protected(map_id,cell):stats.protected_walk+=1
    elif b.quest_helper.places.links(map_id).has(cell):stats.door_walk+=1
    else:stats.unaudited_walk+=1
    if int(spec.job) in [1,30] and old_map==10201 and map_id==10201 and saw_undersea_portal:
     check(old==Vector2i(6,4),"Stop at the FIRST real protected step after original10201 arrival")
     reached=true;stats.stop_kind="first_10201_protected_walk"
   previous_was_door_walk=not fast and old_map==map_id and b.quest_helper.places.links(map_id).has(cell)
   check(b.quest_arrival.has_arrival(b,map_id,cell),"Real route preserves required arrival authority")
  while not packets.is_empty():
   var observed:Dictionary=packets.pop_front()
   if observed.packet.get("quest_ack_required",false):ack(b,observed.packet)
  if int(spec.job)==11 and Rules.flag(b.session._profile,"now",2) and 2415 in b.session._profile.original_items:
   reached=true;stats.stop_kind="original_shell_sp0_request_committed"
  check(not b.battle_open,"Explicit no-random compatibility fixture stays battle-free")
  ticks+=1
  if ticks%100==0:await process_frame
 stats.terminal={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"step":b.quest_auto.step.duplicate(true),"phase":b.quest_auto.phase}
 stats.field_calls=b.field_calls.size()
 stats.reached=reached
 stats.actual_new_benefit=not stats.new_audits.is_empty()
 stats.fallback_only=stats.new_audits.is_empty()
 check(reached,"Reach only the declared incremental terminal: "+str(spec.label)+" / "+b.quest_auto.message)
 var event_id:int={1:4,11:2,30:1}[int(spec.job)]
 check(not Rules.flag(b.session._profile,"ended",event_id),"Do not rerun or claim original whole quest completion")
 if int(spec.job) in [1,30]:
  check(stats.protected_walk==1 and not Rules.flag(b.session._profile,"now",event_id) and b.session._profile.original_items.is_empty(),"Stop before adult/herb request, gates or full cave chain; exactly one protected walk")
 else:
  check(b.automation.position_map==1000 and b.session._profile.original_items==[2415],"Real SP0 request grants original2415, no exchange/reward completion")
 # Missing new-audit hit is honestly reported as fallback; never change A/goal.
 b.handle({"type":"quest_auto_stop"})
 readback(b,"legacy-"+str(spec.label)+"-"+mode)
 stats.wall_ms=Time.get_ticks_msec()-started
 summaries.append(stats)
 print("PUBLIC LEGACY APPROACH ",JSON.stringify(stats))
 b.event.disconnect(observer)
func run()->void:
 deadline=Time.get_ticks_msec()+140000
 for mode in ["B","C"]:
  for spec in CASES:
   var b=approach_fixture(mode,spec)
   await approach(b,mode,spec)
   b.free()
   if Time.get_ticks_msec()>=deadline:break
  if Time.get_ticks_msec()>=deadline:break
 check(summaries.size()==6 and Time.get_ticks_msec()<deadline,"All six bounded incremental approaches finish in allocated window")
 var output=FileAccess.open("user://public-corridors-legacy-approach-results.json",FileAccess.WRITE)
 if output!=null:output.store_string(JSON.stringify({"summaries":summaries,"assertions":assertions,"failures":failures}));output.close()
 check(output!=null,"Retain actual incremental targets, boundaries and fallback results")
 print("QUEST AUTO PUBLIC CORRIDORS LEGACY APPROACH: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Time.get_ticks_msec()-began])
 quit(1 if failures else 0)
