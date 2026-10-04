extends SceneTree
## One separately authorized level35 or level55 pilot. No retry, refill, private answers or RNG seed.
## Controlled audit only, not routine full: legitimate RNG ticket exhaustion
## returns boundary status/exit2 and must not be hidden by automatic retries.
const Session=preload("res://server/game_session.gd")
const Rules=preload("res://server/original_quests.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const BUDGET_MS:=300000
const MAX_TICKS:=10000
class Backend extends "res://server/backend.gd":
 var trace_tick:=0
 var field_steps:=0
 var saved_transactions:Array=[]
 var spent:Dictionary={"2755":0,"2756":0,"2752":0,"2751":0,"2753":0}
 static func items(profile:Dictionary,id:int)->int:
  var total:=0
  for item in profile.get("original_items",[]):
   if int(item)==id:total+=1
  return total
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_steps+=1
  return super._cmd_field_step(command)
 func _save_profile_boundary()->bool:
  var prior:String=last_saved_payload
  var ok:bool=super._save_profile_boundary()
  if not ok or save_path.is_empty() or prior.is_empty() or prior==last_saved_payload:return ok
  var before:Dictionary=JSON.parse_string(prior)
  var after:Dictionary=JSON.parse_string(last_saved_payload)
  var debit:Dictionary={}
  for key in spent:
   var used:int=maxi(0,items(before,int(key))-items(after,int(key)))
   if used>0:spent[key]+=used;debit[key]=used
  var entry:Dictionary={"tick":trace_tick,"step":quest_auto.identity.step_id,"save_serial":quest_save_serial,"debit":debit,"location":after.get("location",{}),"completed_battles":after.get("completed_battles",[]).size()}
  saved_transactions.append(entry)
  print("SAVED ",JSON.stringify(entry))
  return ok
var pilot_level:=int(OS.get_environment("STONE_AGE_GOLDEN_PILOT_LEVEL")) if not OS.get_environment("STONE_AGE_GOLDEN_PILOT_LEVEL").is_empty() else 35
var started_ms:=Time.get_ticks_msec()
var layers:Array=[]
var public_results:Array=[]
var fists:Dictionary={"wins":0,"draws":0,"losses":0}
var seen_draws:Dictionary={}
var last_map:=-1
var b
func _initialize()->void:call_deferred("run")
func on_event(message:Dictionary)->void:
 if message.get("type")=="position" and int(message.get("map_id",-1))!=last_map:
  last_map=int(message.map_id)
  var entry:Dictionary={"tick":b.trace_tick,"map_id":last_map,"cell":message.cell.duplicate(),"step":b.quest_auto.identity.step_id,"proof":b.quest_arrival.has_arrival(b,last_map,b.automation.position_cell)}
  layers.append(entry);print("LAYER ",JSON.stringify(entry))
 if message.get("type")=="quest_result":
  var text:String=str(message.get("text",""))
  var entry:Dictionary={"tick":b.trace_tick,"map_id":b.automation.position_map,"step":b.quest_auto.identity.step_id,"text":text}
  if text.begins_with("你出"):
   if text.contains("获胜"):fists.wins+=1
   elif text.contains("落败"):fists.losses+=1
  public_results.append(entry);print("PUBLIC_RESULT ",JSON.stringify(entry))
func ack()->Dictionary:
 if b.quest_auto.issued.is_empty():return {}
 var p:Dictionary=b.quest_auto.issued[-1]
 var result:Dictionary={"type":"report_position","client":"pilot%d"%pilot_level,"_quest_connection":pilot_level,"map_id":p.map_id,"cell":p.cell.duplicate(),"quest_position_seq":p.seq}
 for key in Motion.IDENTITY_FIELDS:result[key]=p[key]
 return result
func record_draw()->void:
 var frame=b.quest_auto.source_frame
 if frame==null or frame.page.is_empty():return
 var page:Dictionary=frame.page
 if page.get("kind")!="golden_bui_janken" or not str(page.get("text","")).contains("平手") or seen_draws.has(str(page.token)):return
 seen_draws[str(page.token)]=true;fists.draws+=1
 var entry:Dictionary={"tick":b.trace_tick,"map_id":b.automation.position_map,"step":b.quest_auto.identity.step_id,"text":page.text}
 public_results.append(entry);print("PUBLIC_DRAW ",JSON.stringify(entry))
func run()->void:
 if pilot_level not in [35,55]:
  printerr("Unsupported pilot level; no run started");quit(3);return
 var entrance_ticket:=2756 if pilot_level==55 else 2755
 var start_x:=28 if pilot_level==55 else 30
 b=Backend.new();b.set_process(false)
 b.session._profile.player.level=pilot_level
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 b.session._profile.no_random_encounters=false
 Equipment.add(b.session._profile,entrance_ticket)
 for index in range(14):Equipment.add(b.session._profile,2752)
 b.automation.position_changed(811,Vector2i(start_x,22),true)
 b.save_path="user://golden-bui-pilot%d.json"%pilot_level
 var initial:Dictionary=b.session.snapshot()
 var input:Dictionary={"level":initial.player.level,"hp":initial.player.hp,"max_hp":initial.player.max_hp,"attack":initial.player.attack,"defence":initial.player.defence,"speed":initial.player.speed,"base_stats":initial.player.base_stats,"gold":initial.player.gold,"tickets":{str(entrance_ticket):1,"2752":14},"bag_slots":Session.bag_slots(initial),"start":{"map_id":811,"cell":[start_x,22]},"rng":"original randomized; no seed selection or inspection","budget_ms":BUDGET_MS,"max_ticks":MAX_TICKS}
 print("INPUT ",JSON.stringify(input))
 var outcome:="setup_failed"
 var reason:=""
 var setup_ok:bool=Session.bag_slots(initial)==15 and initial.pets.is_empty() and not Rules.flag(initial,"ended",44) and not Rules.flag(initial,"now",44) and b.save()
 var admitted:Dictionary=b.quest_auto.begin_source_run(b,"pilot%d"%pilot_level,pilot_level) if setup_ok else {"ok":false,"reason":"initial input/save mismatch"}
 b.event.connect(on_event)
 var ticks:=0
 var last_step:=""
 if admitted.get("ok",false):
  outcome="running"
  while ticks<MAX_TICKS and Time.get_ticks_msec()-started_ms<BUDGET_MS:
   if not b.quest_auto.running:
    outcome="candidate_complete" if Rules.flag(b.session._profile,"ended",44) else "manual"
    reason=b.quest_auto.message
    break
   ticks+=1;b.trace_tick=ticks
   if b.quest_auto.phase=="landing":
    var position_ack:=ack()
    if position_ack.is_empty():outcome="missing_receipt";reason="landing has no issued authoritative receipt";break
    b.handle(position_ack)
   b._process(0.21)
   record_draw()
   if b.quest_auto.identity.step_id!=last_step:
    last_step=b.quest_auto.identity.step_id
    print("STEP ",JSON.stringify({"tick":ticks,"step":last_step,"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"phase":b.quest_auto.phase}))
  if outcome=="running":
   if not b.quest_auto.running:
    outcome="candidate_complete" if Rules.flag(b.session._profile,"ended",44) else "manual";reason=b.quest_auto.message
   else:outcome="time_limit" if Time.get_ticks_msec()-started_ms>=BUDGET_MS else "tick_limit";reason="pilot budget reached; no retry"
 else:reason=str(admitted.get("reason","admission refused"))
 var final_profile:Dictionary=b.session.snapshot()
 var primary=JSON.parse_string(FileAccess.get_file_as_string(b.save_path)) if FileAccess.file_exists(b.save_path) else null
 var reader=Session.new()
 var primary_valid:bool=reader._valid_profile(primary)
 var reloaded:bool=primary_valid and reader.load_game(b.save_path)
 var disk:Dictionary=reader.snapshot() if reloaded else {}
 var pets:Array=final_profile.get("pets",[])
 var reward_ok:bool=pets.size()==1 and int(pets[0].get("source_enemy_id",-1))==14 and int(pets[0].get("template_id",-1))==12 and int(pets[0].get("quest_reward_event",-1))==44 and int(pets[0].get("level",-1))==1
 var disk_ok:bool=reloaded and Rules.flag(disk,"ended",44) and disk.pets.size()==1 and reward_ok and str(disk.pets[0].pet_id)==str(pets[0].pet_id) and int(disk.pets[0].source_enemy_id)==14 and int(disk.pets[0].level)==1 and Backend.items(disk,2753)==0 and disk.completed_battles==final_profile.completed_battles
 if outcome=="candidate_complete":outcome="complete" if reward_ok and disk_ok and Rules.flag(final_profile,"ended",44) else "completion_validation_failed"
 var report:Dictionary={"outcome":outcome,"reason":reason,"input":input,"ticks":ticks,"simulated_seconds":ticks*0.21,"engine_wall_seconds":(Time.get_ticks_msec()-started_ms)/1000.0,"layers":layers,"fists":fists,"ticket_consumption_saved":b.spent,"remaining_2752":Backend.items(final_profile,2752),"ordinary_battles_saved":final_profile.completed_battles.size(),"field_steps":b.field_steps,"save_receipts":b.saved_transactions,"public_results":public_results,"end44":Rules.flag(final_profile,"ended",44),"reward_exact":reward_ok,"primary_valid":primary_valid,"disk_reloaded":reloaded,"disk_complete":disk_ok,"disk_location":disk.get("location",{}),"disk_end44":Rules.flag(disk,"ended",44) if reloaded else false,"disk_pets":disk.get("pets",[]).size(),"final":{"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"phase":b.quest_auto.phase,"step":b.quest_auto.identity.step_id,"hp":final_profile.player.hp,"pets":pets.size(),"running":b.quest_auto.running},"save_path":ProjectSettings.globalize_path(b.save_path)}
 var file=FileAccess.open("user://golden-bui-pilot%d-result.json"%pilot_level,FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(report,"  "));file.close()
 print("PILOT_RESULT ",JSON.stringify(report))
 print("PILOT_REPORT ",ProjectSettings.globalize_path("user://golden-bui-pilot%d-result.json"%pilot_level))
 b.free()
 quit(0 if outcome=="complete" else 2)
