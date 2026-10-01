extends "res://tests/original_adult_quest_test.gd"
const SAVE="user://adult-quest-resume.json"
func fresh(load_saved:bool=false):
 var b=Backend.new()
 b.set_process(false)
 b.save_path=SAVE
 b.keep_resume_current=true
 if load_saved:check(b.load_profile(SAVE),"real save reloads under v6 authority")
 else:
  clear_bag(b)
  b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
  preload("res://server/progression.gd").refresh(b.session._profile.player)
  b.session._profile.player.hp=b.session._profile.player.max_hp
  b.encounter_rng.seed=7
 return b
func clear_save() -> void:
 for path in [SAVE,SAVE+".bak",SAVE+".tmp",SAVE.get_basename()+".resume.json",SAVE.get_basename()+".resume.json.tmp"]:
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func first_battle(b) -> void:
 check(b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"}).ok,"adult automatic intent starts")
 for i in range(1500):
  if b.quest_auto.phase=="battle":return
  tick(b)
 check(false,"original channel opens real random battle")
func run() -> void:
 for graceful in [false,true]:
  clear_save()
  var b=fresh()
  first_battle(b)
  # Commit a real nonfatal action, then restore exactly that turn/RNG/troop.
  var r:Dictionary=b.battle_command({"action":"defend","target":-1})
  check(r.active and int(r.turn)>0,"real pending turn exists")
  var live:Dictionary=b.battle.snapshot()
  var rng:int=b.battle._rng.state
  var pending:Dictionary=b.session._pending.duplicate(true)
  var checkpoint:Dictionary=preload("res://server/adult_battle_checkpoint.gd").snapshot(b)
  b.keep_resume_file()
  check(FileAccess.file_exists(b._resume_file()),"pending battle checkpoint written to real file")
  if graceful:b.shut_down()
  b.free()
  b=fresh(true);b.load_resume()
  check(b.quest_auto.running and b.quest_auto.restored and b.quest_auto.phase=="battle","resume retains task and automatic battle phase")
  check(b.battle.snapshot().enemies==live.enemies and b.battle.snapshot().turn==live.turn and b.battle._rng.state==rng and b.session._pending==pending,"same original troop, turn, RNG and uncommitted reward restored")
  for i in range(6500):
   if not b.quest_auto.running:break
   tick(b)
  check(Rules.flag(b.session._profile,"ended",4) and b.session._profile.original_items==[2418],"restart completes original exchanges exactly once")
  var completed:Dictionary=b.session.snapshot()
  check(not preload("res://server/adult_battle_checkpoint.gd").restore(b,checkpoint),"settled battle id refuses stale checkpoint and duplicate drops")
  b.load_resume()
  check(b.session.snapshot()==completed,"consumed checkpoint cannot re-award")
  b.free()
 # Real checkpoint files bridge v5/v6 without reinitializing valid v6 gear.
 for legacy in [true,false]:
  clear_save()
  var migrated=fresh()
  if not legacy:
   migrated.session._profile.player.level=30
   Session.OriginalEquipment.add(migrated.session._profile,2427)
   var uid:int=migrated.session._profile.original_instances[0].uid
   migrated.session._profile.original_instances[0].durability=123456
   check(migrated.session.equip_item("original:%d"%uid),"equip real original amulet before battle")
  first_battle(migrated)
  var checkpoint:Dictionary=preload("res://server/adult_battle_checkpoint.gd").snapshot(migrated)
  var expected:Dictionary=migrated.session.snapshot()
  if legacy:
   checkpoint.profile.version=5
   for key in ["original_instances","original_equipment","next_original_uid"]:checkpoint.profile.erase(key)
   var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
   disk.version=5
   for key in ["original_instances","original_equipment","next_original_uid"]:disk.erase(key)
   var out=FileAccess.open(SAVE,FileAccess.WRITE)
   out.store_string(JSON.stringify(disk));out.close()
  migrated._write_resume_file(migrated._resume_file(),{"quest_auto":migrated.quest_auto.resume_state(),"adult_battle":checkpoint,"map_id":10204,"cell":checkpoint.cell})
  migrated.free()
  migrated=fresh(true);migrated.load_resume()
  var after:Dictionary=migrated.session.snapshot()
  check(migrated.battle_open and migrated.quest_auto.running and after.version==6 and migrated.session._valid_profile(after),"real v5/v6 checkpoint resumes validated v6 battle "+str(legacy))
  if not legacy:check(after.original_instances==expected.original_instances and after.original_equipment==expected.original_equipment,"v6 equipment UID and partial durability unchanged")
  migrated.handle({"type":"quest_auto_stop"});migrated.free()
 # Source-position receipt acknowledges only bounded server-issued positions.
 clear_save()
 var b=fresh()
 b.handle({"type":"no_random_encounters","enabled":true})
 b.handle({"type":"quest_auto_start","quest_id":1,"client":"test"})
 for i in range(12):tick(b)
 var receipt:Dictionary=b.quest_auto.issued[-1].duplicate(true)
 tick(b)
 var position:Vector2i=b.automation.position_cell
 check(b.handle({"type":"report_position","map_id":receipt.map_id,"cell":receipt.cell,"quest_position_seq":receipt.seq,"client":"test"}).ok and b.automation.position_cell==position and b.quest_auto.running,"delayed valid receipt cannot rewind or stop task")
 b.handle({"type":"report_position","map_id":10204,"cell":[50,20],"quest_position_seq":receipt.seq,"client":"test"})
 check(not b.quest_auto.running,"forged receipt and real manual displacement stop task")
 b.free()
 for reason in ["manual","stop","party","auto_stop","save_failed"]:
  clear_save();b=fresh();first_battle(b)
  if reason=="manual":b.handle({"type":"report_position","map_id":10204,"cell":[50,20],"client":"other"})
  elif reason=="stop":b.handle({"type":"quest_auto_stop"})
  elif reason=="party":
   b.quest_visit_guard=func():return "party"
   b.quest_auto.tick(b,0.21)
  elif reason=="auto_stop":b.handle({"type":"auto_stop"});b.quest_auto.tick(b,0.21)
  else:
   b.save_path="user://missing-parent/adult.json"
   for i in range(100):
    if not b.quest_auto.running:break
    tick(b)
  check(not b.quest_auto.running and not b.automation.running,"battle ownership stops correctly: "+reason)
  check(b.session._profile.original_items.count(2418)==0,"stopped task never fakes adult reward: "+reason)
  b.free()
 clear_save()
 print("ADULT QUEST RESUME: %d failures" % failures)
 quit(1 if failures else 0)
