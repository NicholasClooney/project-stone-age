extends "res://tests/quest_delivery_routes_test.gd"
const Clock=preload("res://scripts/clock.gd")
## Actual six-job source transactions/routes. Random encounters are explicitly
## disabled ONLY in this mode-compatibility fixture, not natural-battle evidence.
const Arrival=preload("res://server/quest_arrival_policy.gd")
var mode:="B"
var fast_packets:=0
var fallback_walks:=0
var protected_walks:=0
var source_gates:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func mode_fixture(map_id:int,cell:Vector2i):
 var b=fixture(map_id,cell)
 b.session._profile.no_random_encounters=true
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).ok,"Persist selected mode "+mode)
 return b
func mode_drive(b,job:int)->bool:
 var started:int=Clock.ticks_msec()
 var events:Array=[]
 var observe:Callable=func(event):
  if event.get("type")=="position":events.append(event.duplicate(true))
 b.event.connect(observe)
 var result:Dictionary=b.handle({"type":"quest_auto_start","quest_id":job,"client":"compat","_quest_connection":17})
 check(result.get("ok",false) and b.quest_auto.strict_walk,"Start actual "+mode+" job "+str(job))
 if not result.get("ok",false):b.event.disconnect(observe);return false
 var start_moves:int=moves
 var start_fast:int=fast_packets
 var deadline:int=Clock.ticks_msec()+120000
 while b.quest_auto.running and Clock.ticks_msec()<deadline:
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  var gate:bool=b.quest_auto.phase=="strict_dialogue" and b.original_quests.pending.get("phase","")=="FREEWARP"
  events.clear()
  b._process(0.21)
  var map_id:int=b.automation.position_map
  var cell:Vector2i=b.automation.position_cell
  if map_id!=old_map or cell!=old:
   moves+=1
   check(not events.is_empty(),"Actual move publishes a receipt")
   var packet:Dictionary={} if events.is_empty() else events[-1]
   var kind:String=str(packet.get("quest_segment",{}).get("kind",""))
   if map_id!=old_map:
    var portal:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
    var original:bool=not portal.is_empty() and int(portal.to_map)==map_id and Vector2i(portal.target[0],portal.target[1])==cell
    var source_gate:bool=gate and old_map==120 and map_id==122 and cell==Vector2i(6,5)
    check(original or source_gate,"Map change remains exact original portal/FREEWARP")
    if source_gate:source_gates+=1
   elif absi(old.x-cell.x)+absi(old.y-cell.y)!=1:
    check(mode=="B" and kind=="public_jump","Only audited B packet may make a non-adjacent same-map move")
   if kind in ["public_jump","public_stride"]:
    fast_packets+=1
    check(Arrival.scope(map_id).is_empty() and map_id in [100,200,1100,3100] and not Arrival.approach_cell("transmigration_entry",map_id,cell),"Fast packet excludes protected and approach cells")
   elif kind=="walk":
    if not Arrival.scope(map_id).is_empty():protected_walks+=1
    elif not packet.get("quest_ack_required",false):fallback_walks+=1
   check(b.quest_arrival.has_arrival(b,map_id,cell),"Actual source route has required arrival after every move")
  if b.quest_auto.phase in ["landing","segment_landing"] and not b.quest_auto.issued.is_empty():
   var receipt:Dictionary=b.quest_auto.issued[-1]
   var ack:Dictionary={"type":"report_position","client":"compat","_quest_connection":17,"map_id":receipt.map_id,"cell":receipt.cell.duplicate(),"quest_position_seq":receipt.seq}
   for key in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:ack[key]=receipt[key]
   check(b.handle(ack).get("ok",false),"Current complete endpoint/portal ACK accepted")
  check(not b.battle_open,"Explicit encounter-off fixture remains route-only evidence")
 var success:bool=not b.quest_auto.running and Rules.flag(b.session.snapshot(),"ended",Plan.JOB_EVENTS[job])
 check(success,"Complete actual "+mode+" job "+str(job)+": "+b.quest_auto.message)
 print("COMPAT mode=",mode," job=",job," moves=",moves-start_moves," fast=",fast_packets-start_fast," wall_ms=",Clock.ticks_msec()-started)
 b.event.disconnect(observe)
 return success
func run()->void:
 for selected_mode in ["B","C"]:
  mode=selected_mode
  var gate_start:int=source_gates
  var b=mode_fixture(1400,Vector2i(68,90))
  if mode_drive(b,12) and mode_drive(b,13):persisted(b,"compat-"+mode+"-yam")
  b.free()
  b=mode_fixture(200,Vector2i.ZERO)
  var entry:Dictionary=preload("res://server/legacy_cave_helper.gd").entrance(b.quest_helper,b.original_quests.npc_by_id(Plan.SKY))
  b.automation.position_changed(int(entry.from_map),Vector2i(entry.cell[0],entry.cell[1]))
  # Explicit language-shell prerequisite, exactly as the original A route suite.
  # No END6 pet exchange, task flags, receipt or arrival proof is synthesized.
  Session.OriginalEquipment.add(b.session._profile,2414)
  if mode_drive(b,24) and mode_drive(b,25):persisted(b,"compat-"+mode+"-goya")
  b.free()
  b=mode_fixture(1300,Vector2i(69,52))
  if mode_drive(b,5) and mode_drive(b,9):persisted(b,"compat-"+mode+"-marju")
  check(source_gates==gate_start+1,"Each mode uses Marju original FREEWARP exactly once")
  b.free()
 check(protected_walks>0 and fallback_walks>0,"Real six-job protected and unaudited public portions remain original walk")
 print("QUEST DELIVERY MODES COMPAT: %d failures; %d moves; %d fast packets; %d protected walks; %d fallback walks; natural encounters DISABLED fixture"%[failures,moves,fast_packets,protected_walks,fallback_walks])
 quit(1 if failures else 0)
