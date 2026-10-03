extends SceneTree
const Session=preload("res://server/game_session.gd")
const Build=preload("res://server/transmigration_candidate.gd")
const Fixture=preload("res://tests/transmigration_candidate_test.gd")
const Q=preload("res://server/original_quests.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func _initialize()->void:
 var s=Session.new();var path:="user://rebirth-five-round-lifecycle.json"
 s._profile.pets=[Fixture.pet(6,1)];s._profile.pets[0].favorite=true;s._profile.next_pet_id=2
 for count in range(1,6):
  # Prior chain completions/sacrifices are explicit setup; only growth,
  # allocation, candidate persistence and references are under test here.
  while int(s._profile.player.level)<80:s._gain_xp(s._profile.player,int(s._profile.player.level)*30)
  for event in [39,40,42,46]:Q.set_flag(s._profile,"ended",event,true)
  for template in Build.Rules.sacrifice_templates(count):
   s._profile.pets.append(Fixture.pet(template,int(s._profile.next_pet_id)));s._profile.next_pet_id+=1
  s._profile.active_pet=0;s._profile.ride_pet=0
  s._profile.automation_settings={"capture":{"pet":0,"pet_id":"pet-1"}}
  var before:Dictionary=s.snapshot();var ordinary:Dictionary=before.pets[0].duplicate(true)
  var reward:=Build.Rules.reward_for(before.original_savepoint_bits,count)
  var built:=Build.build(before,[],Fixture.definition(reward.enemy_id,reward.template_id),27,"life-%d"%count,Session.PET_CAPACITY)
  check(built.ok and s.commit_transmigration_candidate(built.profile,path),"round %d complete candidate saved"%count)
  if not built.ok:continue
  var p:Dictionary=s.snapshot()
  check(p.pets[0].pet_id=="pet-1" and p.pets[0].favorite and p.pets[0].variable_ai==ordinary.variable_ai and p.pets[0].base_stats==ordinary.base_stats and p.active_pet==0 and p.ride_pet==-1,"round %d preserves ordinary UID/favorite/growth/debt, dismounts"%count)
  check(p.automation_settings.capture.pet_id=="pet-1" and p.automation_settings.capture.pet==0,"round %d capture reference stays on ordinary UID"%count)
  var inherited:Dictionary=p.rebirth.inherited_base.duplicate()
  check(s.allocate_stat("strength",10*count) and s.snapshot().player.stat_points==0,"round %d all new points allocate once"%count)
  s._gain_xp(s._profile.player,30)
  check(s.snapshot().player.level==2 and s.snapshot().player.stat_points==3 and s.allocate_stat("vitality",3),"round %d ordinary XP adds three new allocation points"%count)
  p=s.snapshot()
  check(p.player.base_stats.strength==int(inherited.strength)+1000*count and p.player.base_stats.vitality==int(inherited.vitality)+300 and p.rebirth.inherited_base==inherited and s._valid_profile(p),"round %d inherited fixed base is not double-counted"%count)
  check(s.save_game(path),"round %d allocated growth saves"%count)
  var readback=Session.new()
  check(readback.load_game(path) and readback.snapshot()==s._normalize_numbers(p),"round %d full growth/UID/reference/history readback"%count)
  s=readback
 # Both UID and supported historical index-only capture selections must be
 # invalidated when their selected sacrifice disappears, never retargeted.
 var old=Session.new();old._profile.player.level=80
 for event in [39,40,42,46]:Q.set_flag(old._profile,"ended",event,true)
 old._profile.pets=[Fixture.pet(693,1),Fixture.pet(6,2)];old._profile.next_pet_id=3;old._profile.active_pet=0;old._profile.ride_pet=0
 for capture in [{"pet":0,"pet_id":"pet-1"},{"pet":0}]:
  old._profile.automation_settings={"capture":capture.duplicate()}
  var result:=Build.build(old.snapshot(),[],Fixture.definition(1377,6),27,"removed-ref",30)
  check(result.ok and result.profile.active_pet==-1 and result.profile.ride_pet==-1 and int(result.profile.automation_settings.capture.pet)==-1 and str(result.profile.automation_settings.capture.get("pet_id",""))=="","consumed active/ride/capture reference cleared: "+str(capture))
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("TRANSMIGRATION ROUND LIFECYCLE: %d failures"%failures);quit(1 if failures else 0)
