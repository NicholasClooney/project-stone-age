extends SceneTree
## New public-v2-yam-mati authority execution only; no unchanged full quest chain.
## Mode comparison explicitly disables random encounters. The separate encounter
## suite uses the original encounter catalog and does not mock field_step.
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const AUDIT_ID="public-v2-yam-mati"
const OUTSIDE=Vector2i(621,190)
const DOOR=Vector2i(622,190)
const TARGET=Vector2i(24,59)
class ObservedNavigation extends "res://server/quest_auto_navigation.gd":
 var plan_calls:Array=[]
 var local_calls:Array=[]
 var in_plan:=false
 func plan(b,npc:Dictionary)->Array:
  in_plan=true
  var from:Dictionary={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
  var result:Array=super.plan(b,npc)
  in_plan=false
  plan_calls.append({"from":from,"npc":npc.duplicate(true),"result":result.duplicate(true)})
  return result
 func local_path(b,map_id:int,origin:Vector2i,goal:Vector2i,occupied:Dictionary)->Array:
  # Observe the actual input before super. snapshot() only projects records;
  # never call refresh, plan, blocked or an extra path search for diagnostics.
  var points:Array=occupied.keys()
  points.sort_custom(func(a:Vector2i,c:Vector2i):return a.x<c.x or (a.x==c.x and a.y<c.y))
  var normalized:Array=[]
  for point in points:normalized.append([point.x,point.y,occupied[point]])
  var inputs:Dictionary={"occupied":normalized,"occupied_sha256":JSON.stringify(normalized).sha256_text(),"npc_version":b.original_quests.npc_state.version,"npc_snapshot":b.original_quests.npc_state.snapshot().duplicate(true),"enabled_events":b.quest_catalog.enabled_events.duplicate(),"grid_key_before":grid_key,"block_key_before":block_key}
  var result:Array=super.local_path(b,map_id,origin,goal,occupied)
  local_calls.append({"in_plan":in_plan,"map_id":map_id,"origin":[origin.x,origin.y],"goal":[goal.x,goal.y],"inputs":inputs,"result":result.duplicate(true)})
  return result
class ObservedBackend extends "res://server/backend.gd":
 var field_cells:Array=[]
 var field_results:Array=[]
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_cells.append([int(command.map_id),int(command.cell[0]),int(command.cell[1])])
  var result:Dictionary=super._cmd_field_step(command)
  field_results.append({"command":command.duplicate(true),"reply":result.duplicate(true),"authority":{"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]},"proposal":quest_auto.segment.proposal.duplicate(true),"remaining":quest_auto.segment.remaining(),"retained_route":quest_auto.navigation.route.duplicate(true),"plan_count":quest_auto.navigation.plan_calls.size()})
  return result
var failures:=0
var assertions:=0
var suite_started:int=Time.get_ticks_msec()
var deadline:int=0
func check(value:bool,label:String)->bool:
 assertions+=1
 if not value:failures+=1;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func in_time()->bool:return Time.get_ticks_msec()<deadline
func configure_birth_fixture(_b)->void:
 pass # Original uncontrolled independent-world fixture remains the default.
func fixture(mode:String):
 var b=ObservedBackend.new()
 configure_birth_fixture(b)
 b.quest_auto.navigation=ObservedNavigation.new()
 # Explicit strong-character/mode-compatibility fixture; original event flags,
 # task inventory, receipt and arrival authority are never fabricated.
 b.session._profile.player.level=140
 b.session._profile.player.base_stats={"vitality":12000,"strength":14000,"toughness":14000,"dexterity":3700}
 b.session._profile.player.allocated_stats={"vitality":111,"strength":133,"toughness":140,"dexterity":33}
 b.session._profile.player.stat_points=0
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(1400,Vector2i(68,90))
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).get("ok",false),"Save actual mode preference "+mode)
 check(b.quest_auto.snapshot(b).available_modes.has(mode),"Mode is actually available "+mode)
 return b
func listen(b)->Array:
 var packets:Array=[]
 b.event.connect(func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_segment_id"):packets.append(event.duplicate(true))
 )
 return packets
func acknowledge(b,packet:Dictionary)->void:
 var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":"public-corridors","_quest_connection":17}
 for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:command[field]=packet[field]
 check(b.handle(command).get("ok",false),"Full current initiating-client ACK")
func drain(b,packets:Array)->void:
 while not packets.is_empty():
  var packet:Dictionary=packets.pop_front()
  if packet.get("quest_ack_required",false):acknowledge(b,packet)
func prepare(b,packets:Array)->bool:
 if not check(b.handle({"type":"quest_auto_start","quest_id":12,"client":"public-corridors","_quest_connection":17}).get("ok",false),"Real job12 request starts"):return false
 var ticks:=0
 while b.quest_auto.running and b.automation.position_map!=100 and in_time():
  b.quest_auto.tick(b,0.05)
  drain(b,packets)
  ticks+=1
  if ticks%100==0:await process_frame
 return check(b.automation.position_map==100 and b.automation.position_cell==Vector2i(259,171) and Rules.flag(b.session._profile,"now",3) and 2416 in b.session._profile.original_items,"Real REQUEST gives letter and original village portal reaches reviewed public start")
func proof(b)->Dictionary:
 var arrival=b.quest_arrival
 return {"scope":arrival._scope,"marks":arrival._marks.duplicate(true),"stages":arrival._stages.duplicate(true),"approach":arrival._approach.duplicate(true)}
func persisted(b,label:String)->void:
 var path:String="user://public-corridors-"+label+".json"
 var before:Dictionary=b.session.snapshot()
 check(b.session.save_game(path),"Save normally after actual movement/transaction "+label)
 var restored=Session.new()
 var loaded:bool=restored.load_game(path)
 check(loaded,"Read saved profile "+label)
 if loaded:
  var after:Dictionary=restored.snapshot()
  check(after.original_events==before.original_events and after.original_items==before.original_items,"Readback preserves actual earned request/letter "+label)
  check(restored._profile.completed_battles==b.session._profile.completed_battles,"Readback preserves actual completed battle history "+label)
  check(restored._profile.location==b.session._profile.location,"Readback preserves normally saved location without forcing a destination "+label)
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func route(mode:String)->Dictionary:
 var started:int=Time.get_ticks_msec()
 var b=fixture(mode)
 var packets:Array=listen(b)
 if not await prepare(b,packets):b.free();return {}
 var baseline_proof:Dictionary=proof(b)
 check(baseline_proof=={"scope":"","marks":{},"stages":{},"approach":{}},"Public start has no protected authority")
 var npc:Dictionary=b.original_quests.npc_by_id(str(b.quest_auto.step.npc_id))
 var proposed:Dictionary=Navigation.new().next_segment(b,npc,"C",3)
 if not check(proposed.get("audit_id","")==AUDIT_ID,"Actual current task chooses the new reviewed corridor; do not modify A on mismatch"):
  b.free();return {}
 b.field_cells.clear()
 b.field_results.clear()
 var result:Dictionary={"cells":[],"positions":[],"seconds":0.0,"fast":0,"prefix_max":0,"door_walk":false,"portal":false,"ack_hold":false}
 var ticks:=0
 while b.quest_auto.running and not result.portal and in_time():
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  b.quest_auto.tick(b,0.05)
  if old_map==100 and old!=OUTSIDE and old!=DOOR:result.seconds+=0.05
  var current:Vector2i=b.automation.position_cell
  var current_map:int=b.automation.position_map
  if old_map!=current_map or old!=current:
   result.cells.append([current_map,current.x,current.y])
   result.positions.append({"from":{"map_id":old_map,"cell":[old.x,old.y]},"authority":{"map_id":current_map,"cell":[current.x,current.y]},"phase":b.quest_auto.phase,"proposal":b.quest_auto.segment.proposal.duplicate(true),"remaining":b.quest_auto.segment.remaining(),"plan_count":b.quest_auto.navigation.plan_calls.size()})
   if old_map==100 and current_map==100:
    if current==DOOR:
     result.door_walk=old==OUTSIDE
     check(result.door_walk,"Original door is an independent adjacent walk after the outside cell")
    if absi(current.x-old.x)+absi(current.y-old.y)>1:
     check(mode=="B" and current==OUTSIDE,"Only B jumps, exactly to the door's outside cell")
   if old_map!=current_map:
    result.portal=true
    check(old_map==100 and old==DOOR and current_map==1300 and current==TARGET,"Original portal actually executes on its separate next step")
  while not packets.is_empty():
   var packet:Dictionary=packets.pop_front()
   var segment:Dictionary=packet.get("quest_segment",{})
   if segment.get("kind","") in ["public_jump","public_stride"]:
    check(b.quest_auto.segment.proposal.get("audit_id","")==AUDIT_ID,"Actual executor retains the exact new corridor audit identity")
    result.fast+=1
    var prefix:Array=segment.get("cells",[])
    check(not prefix.is_empty() and prefix[-1].cell==packet.cell,"Only committed prefix ends at the published actual position")
    result.prefix_max=maxi(result.prefix_max,prefix.size())
    if mode=="C":check(prefix.size()<=3,"C prefix never exceeds three logical cells")
    if mode=="B":
     check(current_map==100 and current==OUTSIDE and packet.get("quest_ack_required",false),"B actual landing requires complete ACK outside portal")
     check(proof(b)==baseline_proof,"B project landing creates no scope/marks/stages/approach proof")
     var before_calls:int=b.field_cells.size()
     b.quest_auto.tick(b,0.2)
     check(b.automation.position_cell==OUTSIDE and b.field_cells.size()==before_calls,"B cannot enter the original door before complete ACK")
     result.ack_hold=true
   if packet.get("quest_ack_required",false):acknowledge(b,packet)
  ticks+=1
  if ticks%100==0:await process_frame
 check(result.portal and result.door_walk,"Actual selected corridor finishes through the original door and portal in "+mode+" / "+b.quest_auto.message)
 check((mode=="A" and result.fast==0) or (mode!="A" and result.fast>0),"Mode has real execution evidence "+mode)
 if mode=="B":check(result.ack_hold and result.fast==1,"One new B jump and one explicit ACK boundary")
 result.field_cells=b.field_cells.duplicate(true)
 result.field_results=b.field_results.duplicate(true)
 result.plan_calls=b.quest_auto.navigation.plan_calls.duplicate(true)
 result.local_calls=b.quest_auto.navigation.local_calls.duplicate(true)
 b.handle({"type":"quest_auto_stop"})
 persisted(b,mode)
 b.free()
 print("PUBLIC EXECUTION mode=%s simulated_public_seconds=%.3f fast_packets=%d logical_field_calls=%d wall_ms=%d"%[mode,result.seconds,result.fast,result.field_cells.size(),Time.get_ticks_msec()-started])
 return result
func first_difference(left:Array,right:Array)->Dictionary:
 for index in range(maxi(left.size(),right.size())):
  if index>=left.size() or index>=right.size() or left[index]!=right[index]:
   return {"index":index,"left_size":left.size(),"right_size":right.size(),"left_neighbours":left.slice(maxi(0,index-2),mini(left.size(),index+3)),"right_neighbours":right.slice(maxi(0,index-2),mini(right.size(),index+3))}
 return {}
func run()->void:
 deadline=Time.get_ticks_msec()+55000
 var results:Dictionary={}
 for mode in ["A","C","B"]:
  results[mode]=await route(mode)
  if results[mode].is_empty() or not in_time():break
 if results.has("B") and not results.A.is_empty() and not results.C.is_empty() and not results.B.is_empty():
  var differences:Dictionary={"positions":first_difference(results.A.cells,results.C.cells),"field_steps":first_difference(results.A.field_cells,results.C.field_cells)}
  print("PUBLIC EXECUTION FIRST DIFFERENCES ",JSON.stringify(differences))
  var trace_path:="user://public-corridors-execution-traces.json"
  var trace=FileAccess.open(trace_path,FileAccess.WRITE)
  if trace!=null:
   trace.store_string(JSON.stringify({"differences":differences,"modes":results}))
   trace.close()
  check(trace!=null,"Persist complete passive diagnostic arrays")
  print("PUBLIC EXECUTION TRACE ",ProjectSettings.globalize_path(trace_path))
  check(results.A.cells==results.C.cells,"New corridor complete actual A/C movement sequence including original portal is identical")
  check(results.A.field_cells==results.C.field_cells,"A/C call original field_step on the identical full logical cell sequence")
  check(results.C.seconds>0.0 and absf(results.A.seconds/results.C.seconds-2.0)<0.05,"C is approximately twice A by simulated public travel time, not wall time")
  check(results.B.seconds<results.C.seconds,"B audited public landing uses less simulated movement time")
 else:check(false,"All three actual modes must finish within the allocated short suite")
 check(in_time(),"Suite condition deadline not exceeded")
 print("QUEST AUTO PUBLIC CORRIDORS EXECUTION: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Time.get_ticks_msec()-suite_started])
 quit(1 if failures else 0)
