extends SceneTree
## C ONLY: actual Marju job5 -> job9, original FREEWARP and maze/exit.
## Explicit encounter-off route compatibility, never natural-battle evidence.
## No task item, event, arrival proof, original enemy or reward manipulation.
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Arrival=preload("res://server/quest_arrival_policy.gd")
const Extra=preload("res://server/quest_auto_public_corridors.gd")
const PublicRoutes=preload("res://server/quest_auto_public_routes.gd")
class CountedBackend extends "res://server/backend.gd":
 var field_calls:Array=[]
 func _cmd_field_step(command:Dictionary)->Dictionary:
  var result:Dictionary=super._cmd_field_step(command)
  field_calls.append({"map_id":int(command.map_id),"cell":command.cell.duplicate(),"result":result.duplicate(true)})
  return result
var assertions:=0
var failures:=0
var began:int=Time.get_ticks_msec()
var deadline:int=0
var summaries:Array=[]
func check(value:bool,label:String)->bool:
 assertions+=1
 if not value:failures+=1;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func fixture(mode:String):
 var b=CountedBackend.new()
 # Fixed a priori NPC birth seed only, before any refresh. Normal births run;
 # no field/battle RNG manipulation or clearing existing NPC records.
 check(b.original_quests.npc_state.version==0 and b.original_quests.npc_state.records.is_empty() and b.original_quests.npc_state.spawn_attempts.is_empty(),"Fresh original NPC world before deterministic birth fixture")
 b.original_quests.npc_state.spawn_rng.seed=1
 # Explicit strong legal-level/stat fixture used by original route acceptance.
 b.session._profile.player.level=140
 b.session._profile.player.base_stats={"vitality":12000,"strength":14000,"toughness":14000,"dexterity":3700}
 b.session._profile.player.allocated_stats={"vitality":111,"strength":133,"toughness":140,"dexterity":33}
 b.session._profile.player.stat_points=0
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(1300,Vector2i(69,52))
 check(b.session._profile.original_items.is_empty() and not Rules.flag(b.session._profile,"ended",37) and not Rules.flag(b.session._profile,"ended",38),"Each mode starts with fresh task items and END flags")
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).get("ok",false),"Mode preference saves normally "+mode)
 check(b.quest_auto.snapshot(b).available_modes.has(mode),"Mode is actually available "+mode)
 return b
func ack(b,packet:Dictionary)->void:
 var command:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":"public-marju-c","_quest_connection":17}
 for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:command[field]=packet[field]
 check(b.handle(command).get("ok",false),"Full exact initiating-client position ACK")
func readback(b,label:String)->void:
 var path:String="user://public-marju-c-"+label+".json"
 var before:Dictionary=b.session.snapshot()
 check(b.session.save_game(path),"Actual earned chain state saves "+label)
 var restored=Session.new()
 var loaded:bool=restored.load_game(path)
 check(loaded,"Actual saved state reloads "+label)
 if loaded:
  var after:Dictionary=restored.snapshot()
  check(after.original_events==before.original_events and after.original_items==before.original_items,"Original END/NOW and reward/consumption survive readback "+label)
  check(after.location==b.session._profile.location,"Normal saved location survives readback, no forced endpoint "+label)
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func walk_protected(map_id:int,cell:Vector2i)->bool:
 return not Arrival.scope(map_id).is_empty() or map_id in [10201,10202,10203,120,121] or Arrival.approach_cell("transmigration_entry",map_id,cell)
func reviewed_lane(id:String)->Dictionary:
 for lane in Extra.LANES+PublicRoutes.LANES:
  if lane.id==id:return lane
 return {}
func drive(b,mode:String,job:int)->bool:
 var started:int=Time.get_ticks_msec()
 var event_id:int=37 if job==5 else 38
 var letter:int=2687
 if job==9:
  check(b.automation.position_map==119 and Rules.flag(b.session._profile,"ended",37) and 2697 in b.session._profile.original_items,"Job9 continues from actual Kaite delivery in119 with earned END37/cutting stone")
 var packets:Array=[]
 var observer:Callable=func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_segment_id"):
   packets.append({"packet":event.duplicate(true),"proposal":b.quest_auto.segment.proposal.duplicate(true)})
 b.event.connect(observer)
 var stats:Dictionary={"mode":mode,"job":job,"moves":0,"field_calls":0,"new_audits":{},"old_audits":{},"fast_packets":0,"fast_segments":0,"protected_walk":0,"unaudited_walk":0,"door_walk":0,"original_portals":0,"simulated_total_seconds":0.0,"public_map100_simulated_seconds":0.0,"protected_simulated_seconds":0.0,"source_freewarps":0,"map_transitions":[],"visited_maps":[]}
 var segment_ids:Dictionary={}
 var saw_letter:=false
 var start_fields:int=b.field_calls.size()
 var response:Dictionary=b.handle({"type":"quest_auto_start","quest_id":job,"client":"public-marju-c","_quest_connection":17})
 var started_ok:bool=check(response.get("ok",false) and b.quest_auto.strict_walk,"Actual original job starts %s/%d"%[mode,job])
 var ticks:=0
 while started_ok and b.quest_auto.running and Time.get_ticks_msec()<deadline:
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  var original_gate:bool=b.quest_auto.phase=="strict_dialogue" and b.original_quests.pending.get("phase","")=="FREEWARP" and b.quest_auto.step.get("npc_id","")=="genout/wpm_120_19_15@120:19:15"
  b.quest_auto.tick(b,0.05)
  stats.simulated_total_seconds+=0.05
  if old_map==100:stats.public_map100_simulated_seconds+=0.05
  if walk_protected(old_map,old):stats.protected_simulated_seconds+=0.05
  if not old_map in stats.visited_maps:stats.visited_maps.append(old_map)
  if job==5 and letter in b.session._profile.original_items and Rules.flag(b.session._profile,"now",37):saw_letter=true
  var map_id:int=b.automation.position_map
  var cell:Vector2i=b.automation.position_cell
  if old_map!=map_id or old!=cell:
   stats.moves+=1
   check(not packets.is_empty(),"Actual movement publishes a task receipt")
   var observed:Dictionary=packets[-1] if not packets.is_empty() else {}
   var packet:Dictionary=observed.get("packet",{})
   var proposal:Dictionary=observed.get("proposal",{})
   var kind:String=str(packet.get("quest_segment",{}).get("kind","walk"))
   if kind in ["public_jump","public_stride"]:
    var id:String=str(proposal.get("audit_id",""))
    var lane:Dictionary=reviewed_lane(id)
    check(not lane.is_empty(),"Actual fast movement has an exact reviewed lane identity")
    check(old_map==map_id and not walk_protected(map_id,cell) and not b.quest_helper.places.links(map_id).has(cell),"Fast movement stays outside original doors and all protected/approach cells")
    check((mode=="B" and kind=="public_jump") or (mode=="C" and kind=="public_stride"),"Actual fast kind follows selected mode")
    if not lane.is_empty():check(int(lane.map)==map_id,"Exact reviewed lane matches authority map")
    var prefix:Array=packet.quest_segment.get("cells",[])
    check(not prefix.is_empty() and prefix[-1].cell==packet.cell and prefix.size()<=3,"Actual C committed prefix is bounded to three cells and ends at authority")
    check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"Each actual C commit executes exactly one original adjacent logical cell")
    var preceding:Array=packet.quest_segment.get("from_cell",[])
    for point in prefix:
     check(preceding.size()==2 and absi(int(point.cell[0])-int(preceding[0]))+absi(int(point.cell[1])-int(preceding[1]))==1,"Entire published C prefix preserves adjacent logical cells from its actual origin")
     preceding=point.cell
    stats.fast_packets+=1
    var group:Dictionary=stats.new_audits if Extra.LANES.any(func(value):return value.id==id) else stats.old_audits
    if not group.has(id):group[id]={"packets":0,"segments":0}
    group[id].packets+=1
    var segment_id:String=str(packet.quest_segment_id)
    if not segment_ids.has(segment_id):
     segment_ids[segment_id]=true;stats.fast_segments+=1;group[id].segments+=1
   elif old_map!=map_id:
    var portal:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
    var original_portal:bool=not portal.is_empty() and int(portal.to_map)==map_id and Vector2i(portal.target[0],portal.target[1])==cell
    var source_gate:bool=original_gate and old_map==120 and map_id==122 and cell==Vector2i(6,5)
    check(original_portal or source_gate,"Map change is exact original portal or reviewed original FREEWARP transaction")
    stats.map_transitions.append({"from_map":old_map,"from_cell":[old.x,old.y],"to_map":map_id,"to_cell":[cell.x,cell.y],"source":portal.get("source","") if original_portal else "genout/wpm_120_19_15","kind":"portal" if original_portal else "source_freewarp"})
    if source_gate:stats.source_freewarps+=1
    else:stats.original_portals+=1
   else:
    check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"All non-fast movement is one original logical cell")
    if walk_protected(old_map,old) or walk_protected(map_id,cell):stats.protected_walk+=1
    elif b.quest_helper.places.links(map_id).has(cell):stats.door_walk+=1
    else:stats.unaudited_walk+=1
   check(b.quest_arrival.has_arrival(b,map_id,cell),"Original route retains any required legitimate arrival")
  while not packets.is_empty():
   var observed:Dictionary=packets.pop_front()
   if observed.packet.get("quest_ack_required",false):ack(b,observed.packet)
  check(not b.battle_open,"Explicit encounter-off compatibility fixture remains battle-free")
  ticks+=1
  if ticks%100==0:await process_frame
 var complete:bool=not b.quest_auto.running and Rules.flag(b.session._profile,"ended",event_id)
 check(complete,"Actual original chain job completes %s/%d: %s"%[mode,job,b.quest_auto.message])
 if job==5:check(saw_letter,"Observed actual original mail2687 request and NOW37 before Kaite delivery")
 if complete:
  check(letter not in b.session._profile.original_items,"Original delivery consumes actual held letter")
  check(b.session._profile.original_items.count(2697)==1,"Actual Kaite cutting stone2697 is earned and retained")
  var reward_count:int=0
  for reward in [2688,2689,2690]:reward_count+=b.session._profile.original_items.count(reward)
  if job==5:
   check(reward_count==0,"Original Kaite delivery does not prematurely grant Marju random return reward")
   check(stats.source_freewarps==1 and 122 in stats.visited_maps and 118 in stats.visited_maps and 119 in stats.visited_maps,"Actual5 uses exactly one original FREEWARP and original maze route")
  else:
   check(reward_count==1 and Rules.flag(b.session._profile,"ended",37),"Original return grants exactly one allowed random reward and preserves END37")
   check(stats.source_freewarps==0 and b.automation.position_map==1300,"Actual9 uses original maze exit back to Marju, no repeated script entry")
  readback(b,"%s-%d"%[mode,job])
 stats.field_calls=b.field_calls.size()-start_fields
 stats.wall_ms=Time.get_ticks_msec()-started
 stats.complete=complete
 stats.saw_actual_letter=saw_letter
 stats.final_original_items=b.session._profile.original_items.duplicate()
 stats.ended37=Rules.flag(b.session._profile,"ended",37)
 stats.ended38=Rules.flag(b.session._profile,"ended",38)
 check(stats.field_calls==stats.moves-stats.original_portals-stats.source_freewarps,"Logical original field-step calls match moves minus original portals and script gate")
 check(stats.protected_walk>0,"Original maze/staging rooms retain actual protected adjacent walk")
 check(not stats.new_audits.is_empty(),"Actual job has new reviewed-lane benefit; fail honestly if A selected another path")
 summaries.append(stats)
 print("PUBLIC MARJU C JOB ",JSON.stringify(stats))
 b.event.disconnect(observer)
 return complete
func run()->void:
 deadline=Time.get_ticks_msec()+170000
 for mode in ["C"]:
  var b=fixture(mode)
  if await drive(b,mode,5):await drive(b,mode,9)
  b.free()
  if Time.get_ticks_msec()>=deadline:break
 check(summaries.size()==2,"C mode completes both actual jobs5/9")
 check(Time.get_ticks_msec()<deadline,"Original complete routes fit allocated condition deadline")
 var path:="user://public-corridors-marju-c-results.json"
 var output=FileAccess.open(path,FileAccess.WRITE)
 if output!=null:output.store_string(JSON.stringify({"summaries":summaries,"assertions":assertions,"failures":failures}));output.close()
 check(output!=null,"Retain per-job real benefit/transaction evidence")
 print("PUBLIC MARJU C TRACE ",ProjectSettings.globalize_path(path))
 print("QUEST AUTO PUBLIC CORRIDORS MARJU C: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Time.get_ticks_msec()-began])
 quit(1 if failures else 0)
