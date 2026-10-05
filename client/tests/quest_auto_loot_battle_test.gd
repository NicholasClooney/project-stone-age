extends "res://tests/quest_auto_loot_state_test.gd"
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
## Internal prepared-span fixture only: actual original area roll/battle/save,
## not public activation, source-plan acceptance or natural farming success.
const Backend=preload("res://server/backend.gd")
func prepare(b,setup:Callable=Callable())->bool:
 b.set_process(false)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.session.OriginalEquipment.add(b.session._profile,2764)
 if setup.is_valid():setup.call(b)
 if failures:return false
 var found:=false
 for y in range(341,413):
  for x in range(621,646):
   var cell:=Vector2i(x,y)
   if b.encounter_catalog.area_at(100,cell).get("id")!=56:continue
   b.automation.position_changed(100,cell,true,"project")
   if b.encounter_position_error(100,cell).is_empty():found=true;break
  if found:break
 if not found:check(false,"Original public source area has actual usable cell");return false
 var q=b.quest_auto
 q.identity.begin();q.identity.select_step(KEY)
 q.running=true;q.internal=true;q.detached=false;q.connection=71;q.client="loot-internal-fixture"
 q.step=preload("res://server/quest_auto_loot_sources.gd").step();q.phase="loot_fixture"
 var created:Dictionary=State.acquire(b.session._profile.quest_loot,KEY,ID,q.identity.run_id,30,0)
 check(created.get("ok",false),"Prepared ledger acquire succeeds")
 if failures:return false
 var opened_span:Dictionary=State.open(created.ledger,KEY,State.identity(created.ledger.entries[KEY]))
 check(opened_span.get("ok",false),"Prepared ledger open succeeds")
 if failures:return false
 b.session._profile.quest_loot=opened_span.ledger
 if not b.save():check(false,"Prepared span must persist before original encounter");return false
 check(b.quest_loot.start_after_commit(KEY,b.session._profile.quest_loot.entries[KEY],q.identity.checkpoint()),"Internal clock starts from actual saved span")
 if failures:return false
 # Normal weighted local roll, not an injected enemy/group or winning seed.
 var opened:Dictionary=b.wild_encounter(100,b.automation.position_cell)
 q.internal=false
 if not opened.ok:check(false,"Real original local group roll "+str(opened));return false
 check(b.session._pending.has("quest_loot_receipt"),"Every actually rolled same-area group binds a receipt")
 return b.session._pending.has("quest_loot_receipt")
func finish(b)->bool:
 for turn in range(100):
  if failures:return false
  if not b.battle.snapshot().active:return true
  var target:=0
  for i in range(b.battle._state.enemies.size()):
   if int(b.battle._state.enemies[i].hp)>0:target=i;break
  var reply:Dictionary=b.handle({"type":"battle_command","action":"attack","target":target})
  check(reply.get("ok",false),"Original attack command accepted")
  if failures:return false
 check(not b.battle.snapshot().active,"Original battle settles within explicit fixture ceiling")
 return failures==0
func run()->void:
 for fail_save in [false,true]:
  var b=Backend.new();b.save_path="user://loot-real-battle-%s.json"%str(fail_save)
  if not prepare(b):b.free();quit(1);return
  var pending:Dictionary=b.session._pending.duplicate(true)
  var before:Dictionary=b.session.snapshot()
  var previous_disk:=FileAccess.get_file_as_string(b.save_path)
  b.quest_auto.stop(b,"Fixture cancels continuation, not original battle accounting")
  if fail_save:
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own tmp blocker created")
   if failures:b.free();quit(1);return
  if not finish(b):b.free();quit(1);return
  if fail_save:
   check(not b.battle_state.get("settled",false) and b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==previous_disk,"Real write failure rolls back battle reward and ledger together")
   if failures:b.free();quit(1);return
   check(b.session._pending.has("quest_loot_receipt") and b.session._pending.quest_loot_receipt==pending.quest_loot_receipt,"Original receipt retained for same battle retry")
   if failures:b.free();quit(1);return
   check(not b.handle({"type":"battle_close"}).ok and b.session.snapshot()==before,"Repeated failed original close cannot count")
   if failures:b.free();quit(1);return
   check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Own tmp blocker removed only after failed-save checks")
   if failures:b.free();quit(1);return
   check(b.handle({"type":"battle_close"}).ok,"Same original battle retries after storage repair")
   if failures:b.free();quit(1);return
  else:check(b.battle_state.get("settled",false),"Successful original battle committed")
  if failures:b.free();quit(1);return
  var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
  var received:=0
  for drop in b.battle_state.get("drop_summary",[]):
   if drop.item_id==2760 and drop.received:received+=1
  check(entry.saved_battles==1 and entry.new_items==received and not entry.open_span,"Exactly saved battle and actually received target items counted")
  if failures:b.free();quit(1);return
  var disk_copy:Dictionary=ProfileCompare.validated_copy(b.session,FileAccess.get_file_as_string(b.save_path))
  check(disk_copy.ok,"Complete battle disk profile validates before comparison normalization")
  if failures:b.free();quit(1);return
  check(disk_copy.profile==b.session.snapshot() and str(pending.battle_id) in disk_copy.profile.completed_battles,"Real disk atomically contains full original reward/UID/profile and counters")
  if failures:b.free();quit(1);return
  check(not b.quest_auto.running,"Cancelled runner never revived by accounting commit")
  if failures:b.free();quit(1);return
  var counted:int=entry.saved_battles
  b.handle({"type":"battle_close"})
  check(b.session._profile.quest_loot.entries[KEY].saved_battles==counted,"Late close never duplicates accounting")
  if failures:b.free();quit(1);return
  b.free()
 print("QUEST AUTO LOOT BATTLE: %d failures; dormant internal prepared-span fixture"%failures)
 quit(1 if failures else 0)
