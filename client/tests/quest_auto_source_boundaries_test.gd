extends SceneTree
## Fixed scheduler boundaries only: encounters explicitly disabled, no seed.
## Runtime cases enter through the real public gate; capacity cases are pure
## validated profile copies, never protected placement or arrival stubs.
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Plan=preload("res://server/quest_auto_golden_bui_plan.gd")
const Rules=preload("res://server/original_quests.gd")
class Backend extends "res://server/backend.gd":
 var field_calls:=0
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_calls+=1
  return super._cmd_field_step(command)
var failures:=0
var assertions:=0
var serial:=0
func check(value:bool,label:String)->bool:
 assertions+=1
 if not value:failures+=1;push_error(label)
 return value
func _initialize()->void:call_deferred("run")
func fresh(gate:bool=true,quiz:bool=false):
 serial+=1
 var b=Backend.new();b.set_process(false)
 b.session._profile.player.level=35
 b.session._profile.no_random_encounters=true # Fixed boundary fixture, not natural route evidence.
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 if gate:Equipment.add(b.session._profile,2755)
 if quiz:Equipment.add(b.session._profile,2752)
 b.automation.position_changed(811,Vector2i(30,22),true)
 b.save_path="user://source-boundary-%d.json"%serial
 check(b.session._valid_profile(b.session.snapshot()) and b.save(),"Valid persisted public-entry fixture")
 return b
func snapshot(b)->Dictionary:
 return {"profile":b.session.snapshot(),"disk":FileAccess.get_file_as_string(b.save_path),"position":[b.automation.position_map,b.automation.position_cell],"identity":b.quest_auto.identity.checkpoint(),"serial":b.quest_save_serial,"field_calls":b.field_calls,"pending":b.original_quests.pending.duplicate(true),"issued":b.quest_auto.issued.duplicate(true)}
func ack(b)->Dictionary:
 if b.quest_auto.issued.is_empty():return {}
 var p:Dictionary=b.quest_auto.issued[-1]
 var result:Dictionary={"type":"report_position","map_id":p.map_id,"cell":p.cell.duplicate(),"quest_position_seq":p.seq,"client":"boundary","_quest_connection":71}
 for key in Motion.IDENTITY_FIELDS:result[key]=p[key]
 return result
func tick(b)->void:b._process(0.21)
func reach(b,predicate:Callable)->bool:
 for index in range(160):
  if predicate.call():return true
  if not b.quest_auto.running:return false
  if b.quest_auto.phase=="landing":b.handle(ack(b))
  tick(b)
 return predicate.call()
func begin(b)->bool:return check(b.quest_auto.begin_source_run(b,"boundary",71).get("ok",false),"Internal admission respects actual public source")
func enter(b)->Dictionary:
 if not begin(b):return {}
 if not check(reach(b,func():return b.quest_auto.phase=="landing"),"Real original gate reaches landing"):return {}
 check(b.automation.position_map==800 and b.quest_arrival.has_arrival(b,800,b.automation.position_cell),"Saved original gate alone grants arrival proof")
 check(not 2755 in b.session._profile.original_items and JSON.parse_string(FileAccess.get_file_as_string(b.save_path)).location.map_id==800,"Original gate consumes and persists its ticket and location")
 var result:=ack(b);b.handle(result)
 return result
func quiz_open(b)->bool:
 return check(reach(b,func():return b.quest_auto.phase=="source_dialogue" and b.quest_auto.step.id=="golden44:challenge:genout/quz_800_29_19"),"Real original walk reaches first quiz confirm")
func stale_choice(b,token:String,identity:Dictionary)->Dictionary:
 var command:Dictionary={"type":"quest_choose","token":token,"choice":"yes","client":"boundary","_quest_connection":71}
 command.quest_run_id=identity.get("run_id","")
 command.quest_step_id=identity.get("step_id","")
 command.quest_revision=identity.get("revision",-1)
 return b.handle(command)
func stopped(b,old_ack:Dictionary={},token:String="",old_identity:Dictionary={})->void:
 var before:=snapshot(b)
 if not old_ack.is_empty():b.handle(old_ack)
 if not token.is_empty():check(not stale_choice(b,token,old_identity).get("ok",false),"Stopped old public token refuses")
 for index in range(12):tick(b)
 check(not b.quest_auto.running and b.quest_auto.source_frame==null,"Stopped runner/frame do not revive")
 check(snapshot(b)==before,"Old packet and later ticks leave profile/disk/identity/position/field/save/pending/receipt unchanged")
 check(not Rules.flag(b.session._profile,"ended",44) and b.session._profile.pets.is_empty(),"Boundary never invents completion or pet reward")
func missing_tickets()->void:
 var b=fresh(false)
 var before:=snapshot(b)
 check(not b.handle({"type":"quest_auto_start","quest_id":2}).get("ok",false),"Public job2 remains closed")
 var reply:Dictionary=b.quest_auto.begin_source_run(b,"boundary",71)
 check(not reply.ok and reply.reason=="缺少原入场券，请手动购买；自动任务不代购。","Missing entrance ticket refuses immediately")
 check(snapshot(b)==before,"Refused admission has no state or disk effect")
 stopped(b);b.free()
 b=fresh()
 var old_ack:=enter(b)
 tick(b)
 check(b.quest_auto.phase=="manual" and b.quest_auto.pause_reason=="缺少猜谜的参加票2752，请手动取得后继续。","Real gate followed by missing quiz ticket hands off precisely")
 stopped(b,old_ack);b.free()
func save_failure(quiz:bool)->void:
 var b=fresh(true,quiz)
 var old_ack:Dictionary={}
 if quiz:
  old_ack=enter(b)
  if not quiz_open(b):b.free();return
 else:
  if not begin(b):b.free();return
  tick(b)
  if not check(b.quest_auto.phase=="source_dialogue","Gate confirmation opened before failure"):b.free();return
 var token:String=b.original_quests.pending.token
 var old_identity:Dictionary=b.quest_auto.identity.checkpoint()
 var before:=snapshot(b)
 var blocked:=ProjectSettings.globalize_path(b.save_path+".tmp")
 if not check(DirAccess.make_dir_absolute(blocked)==OK,"Actual tmp directory blocks candidate writer"):b.free();return
 tick(b)
 check(b.quest_auto.phase=="manual" and b.quest_auto.pause_reason=="save_failed","Scheduler stops on actual original save failure")
 var after:=snapshot(b)
 for key in ["profile","disk","position","serial","field_calls"]:check(after[key]==before[key],"Save failure rolls back "+key)
 check(b.original_quests.pending.is_empty() and b.quest_auto.issued.is_empty(),"Failed token and movement receipt cleared")
 if not quiz:check(not b.quest_arrival.has_arrival(b,800,Vector2i(14,26)),"Failed gate has no protected proof")
 check(DirAccess.remove_absolute(blocked)==OK,"Only fixture tmp blocker removed")
 stopped(b,old_ack,token,old_identity)
 b.free()
func paid_cancel()->void:
 var b=fresh(true,true)
 var old_ack:=enter(b)
 if not quiz_open(b):b.free();return
 tick(b)
 check(b.quest_auto.phase=="source_dialogue" and not 2752 in b.session._profile.original_items,"Actual first quiz confirmation paid once")
 check(not 2752 in JSON.parse_string(FileAccess.get_file_as_string(b.save_path)).original_items,"Paid ticket is already on disk")
 var token:String=b.original_quests.pending.token
 var old_identity:Dictionary=b.quest_auto.identity.checkpoint()
 var paid:Dictionary=b.session.snapshot()
 b.quest_auto.stop(b,"explicit paid-page cancellation")
 check(b.session.snapshot()==paid,"Cancellation does not refund committed quiz entry")
 stopped(b,old_ack,token,old_identity)
 b.free()
func pure_capacity()->void:
 var b=fresh(false)
 var live:=snapshot(b)
 var full:Dictionary=b.session.snapshot()
 for index in range(15):Equipment.add(full,2752)
 check(Session.bag_slots(full)==15 and b.session._valid_profile(full),"Pure full-bag profile is genuinely valid")
 var original:=full.duplicate(true)
 var reply:Dictionary=Plan.exchange(b,{},full,810)
 check(reply.status=="manual" and reply.reason=="道具栏已满，请先留出会员证位置。","PURE: capacity refuses before any arrival/action lookup")
 check(full==original and snapshot(b)==live,"PURE full bag has no input/live/disk effects")
 var donor=Session.new()
 for index in range(Session.PET_CAPACITY):check(donor.gm_grant_pet(12,true),"Explicit pure-capacity owned pet input")
 full=donor.snapshot()
 for key in full.inventory:full.inventory[key]=0
 Equipment.add(full,2753);Rules.set_flag(full,"now",44,true)
 check(full.pets.size()==Session.PET_CAPACITY and b.session._valid_profile(full),"Pure full-pet profile is genuinely valid")
 original=full.duplicate(true)
 reply=Plan.exchange(b,{},full,810)
 check(reply.status=="manual" and reply.reason=="随身宠物栏已满，请先空出位置。","PURE: full pets refuse original exchange")
 check(full==original and snapshot(b)==live and not Rules.flag(full,"ended",44),"PURE full pets do not consume/grant/end or touch live state")
 check(b.automation.position_map==811 and not b.quest_arrival.has_arrival(b,810,Vector2i(28,18)),"Capacity fixtures never place in protected room or grant proof")
 b.free()
func run()->void:
 missing_tickets()
 save_failure(false)
 save_failure(true)
 paid_cancel()
 pure_capacity()
 print("QUEST AUTO SOURCE BOUNDARIES: %d assertions, %d failures; runtime=5, pure_capacity=2; no_random_encounters=true; no full-route claim"%[assertions,failures])
 quit(1 if failures else 0)
