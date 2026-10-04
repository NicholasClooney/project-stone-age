extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Plan=preload("res://server/quest_delivery_plan.gd")
var failures:=0
var battles:=0
var moves:=0
var suite_started:int=Time.get_ticks_msec()
func check(value:bool,label:String)->void:
 print(("PASS: " if value else "FAIL: ")+label)
 if not value:failures+=1
func _initialize()->void:call_deferred("run")
func fixture(map_id:int,cell:Vector2i):
 var started:int=Time.get_ticks_msec()
 var b=Backend.new()
 # Public starting position and a legal level/stat allocation are fixtures.
 # No event flags, arrival proof, RNG seeds, encounter suppression or GM calls.
 b.session._profile.player.level=140
 b.session._profile.player.base_stats={"vitality":12000,"strength":14000,"toughness":14000,"dexterity":3700}
 b.session._profile.player.allocated_stats={"vitality":111,"strength":133,"toughness":140,"dexterity":33}
 b.session._profile.player.stat_points=0
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.automation.position_changed(map_id,cell)
 print("TIMING delivery_fixture map=%d wall_ms=%d"%[map_id,Time.get_ticks_msec()-started])
 return b
func rpc(link,command:Dictionary)->Dictionary:
 var replies:Array=[]
 link.request(command,func(reply):replies.append(reply))
 var ready:bool=await preload("res://tests/support/wait.gd").until(self,func():return not replies.is_empty())
 check(ready,"real socket roundtrip")
 return replies[0] if ready else {}
func drive(b,job:int,link=null)->bool:
 var started:int=Time.get_ticks_msec()
 var start:Dictionary={"type":"quest_auto_start","quest_id":job,"client":"delivery-route"}
 var reply:Dictionary=b.handle(start) if link==null else await rpc(link,start)
 check(reply.get("ok",false) and b.quest_auto.strict_walk,"start strict actual runner job %d"%job)
 if not reply.get("ok",false):return false
 var deadline:int=Time.get_ticks_msec()+600000
 var iterations:=0
 var start_moves:=moves
 var start_battles:=battles
 while b.quest_auto.running and Time.get_ticks_msec()<deadline:
  var old_map:int=b.automation.position_map
  var old_cell:Vector2i=b.automation.position_cell
  var gate:bool=b.quest_auto.phase=="strict_dialogue" and b.original_quests.pending.get("phase","")=="FREEWARP"
  var was_battle:bool=b.quest_auto.phase=="battle"
  b._process(0.21)
  var point:Vector2i=b.automation.position_cell
  var map_id:int=b.automation.position_map
  if old_map!=map_id:
   var portal:Dictionary=b.quest_helper.places.links(old_map).get(old_cell,{})
   var walked:bool=not portal.is_empty() and int(portal.to_map)==map_id and Vector2i(int(portal.target[0]),int(portal.target[1]))==point
   var source_gate:bool=gate and old_map==120 and map_id==122 and point==Vector2i(6,5)
   if not walked and not source_gate:check(false,"non-original map jump %d %s -> %d %s"%[old_map,old_cell,map_id,point]);break
   print("PORTAL job=%d %d%s -> %d%s"%[job,old_map,old_cell,map_id,point])
  elif old_cell!=point and absi(point.x-old_cell.x)+absi(point.y-old_cell.y)!=1:
   check(false,"non-adjacent route move %d %s -> %s"%[map_id,old_cell,point]);break
  if old_cell!=point or old_map!=map_id:moves+=1
  if not was_battle and b.quest_auto.phase=="battle":battles+=1
  if b.quest_auto.phase=="landing" and not b.quest_auto.issued.is_empty():
   var receipt:Dictionary=b.quest_auto.issued[-1]
   var report:Dictionary={"type":"report_position","map_id":receipt.map_id,"cell":receipt.cell,"quest_position_seq":receipt.seq,"client":"delivery-route"}
   var ack:Dictionary=b.handle(report) if link==null else await rpc(link,report)
   if not ack.get("ok",false):check(false,"landing rejected "+str(ack));break
  iterations+=1
  if link!=null or iterations%100==0:await process_frame
  if link!=null and iterations%20==0:await rpc(link,{"type":"ping"})
  if iterations%500==0:print("PROGRESS job=%d map=%d cell=%s moves=%d battles=%d phase=%s"%[job,map_id,point,moves-start_moves,battles-start_battles,b.quest_auto.phase])
 var success:bool=not b.quest_auto.running and Rules.flag(b.session.snapshot(),"ended",Plan.JOB_EVENTS[job])
 check(success,"job %d complete; moves=%d battles=%d position=%d%s phase=%s reason=%s"%[job,moves-start_moves,battles-start_battles,b.automation.position_map,b.automation.position_cell,b.quest_auto.phase,b.quest_auto.message])
 print("TIMING delivery_job=%d wall_ms=%d moves=%d battles=%d"%[job,Time.get_ticks_msec()-started,moves-start_moves,battles-start_battles])
 return success
func persisted(b,label:String)->void:
 var path:String="user://delivery-route-"+label+".json"
 check(b.session.save_game(path),"save earned route "+label)
 var restored=Session.new()
 check(restored.load_game(path) and restored.snapshot().original_events==b.session.snapshot().original_events and restored.snapshot().original_items==b.session.snapshot().original_items,"reload earned flags/items "+label)
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func run()->void:
 var b=fixture(1400,Vector2i(68,90))
 if await drive(b,12):
  if await drive(b,13):persisted(b,"yam")
 b.free()
 b=fixture(200,Vector2i.ZERO)
 var entry:Dictionary=preload("res://server/legacy_cave_helper.gd").entrance(b.quest_helper,b.original_quests.npc_by_id(Plan.SKY))
 b.automation.position_changed(int(entry.from_map),Vector2i(int(entry.cell[0]),int(entry.cell[1])))
 # A language shell is an explicit prerequisite fixture; job6 pet exchange
 # is outside this batch and is not executed or credited by this test.
 Session.OriginalEquipment.add(b.session._profile,2414)
 if await drive(b,24):
  if await drive(b,25):persisted(b,"goya")
 b.free()
 b=fixture(1300,Vector2i(69,52))
 if await drive(b,5):
  if await drive(b,9):persisted(b,"marju")
 b.free()
 print("TIMING delivery_suite wall_ms=%d"%(Time.get_ticks_msec()-suite_started))
 print("QUEST DELIVERY ROUTES: %d failures; %d real moves; %d natural encounters"%[failures,moves,battles])
 quit(1 if failures else 0)
