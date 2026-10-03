extends SceneTree
const Session=preload("res://server/game_session.gd")
const State=preload("res://server/transmigration_state.gd")
const Backend=preload("res://server/backend.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if ok:print("PASS: "+label)
 else:failures+=1;push_error("FAIL: "+label)

# Deliberately build historical fields: not a current snapshot with a lower version.
func legacy(version:int)->Dictionary:
 var p:Dictionary={"version":version,"profile_id":"samgir-singleplayer-v1","player":{"hp":40,"max_hp":48,"level":33,"xp":12,"gold":1234567,"attack":10,"defence":0},"inventory":{"potion":2,"club":0},"equipped":false,"pets":[],"active_pet":-1,"quest":{"accepted":false,"wins":0,"boss_defeated":false,"claimed":false},"location":{"map_id":1000,"x":80,"y":90},"completed_battles":[],"next_battle":1}
 if version>=2:p.pet_storage=[];p.next_pet_id=1
 if version>=4:p.player.mp=37;p.equipment={"body":"","amulet":""}
 if version>=5:p.merge(Session.ORIGINAL_DEFAULT.duplicate(true),true)
 if version>=6:
  p.original_instances=[];p.original_equipment={"arm":0,"bracelet":0,"amulet":0};p.next_original_uid=1
 return p
func write_profile(path:String,p:Dictionary)->void:
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(p));f.close()
func candidate(s)->Dictionary:
 var p:Dictionary=s.snapshot()
 p.player.transmigration=1;p.player.level=1;p.player.xp=0;p.player.allocated_stats={"vitality":0,"strength":0,"toughness":0,"dexterity":0}
 p.player.base_stats={"vitality":150,"strength":250,"toughness":350,"dexterity":450};p.player.erase("legacy_stat_offset");p.player.stat_points=10
 p.rebirth={"schema":1,"rules":State.RULES,"history":"natural","equation":(20<<16)|120,"inherited_base":p.player.base_stats.duplicate(),"developer_base_delta":{"vitality":0,"strength":0,"toughness":0,"dexterity":0},"round_points":10,"consumed_gm_points":0,"last_transaction":"test-candidate-1"}
 Session.Progression.refresh(p.player);p.player.hp=p.player.max_hp
 return p
func _initialize()->void:
 var s=Session.new();var fresh:Dictionary=s.snapshot()
 check(s._valid_profile(fresh) and fresh.version==7 and fresh.player.transmigration==0 and fresh.rebirth==State.zero(),"new v7 zero history is explicit")
 for version in range(1,7):
  var old:=legacy(version);var path:="user://rebirth-v%d.json"%version
  check(s._valid_profile(old),"genuine historical shape valid v%d"%version)
  write_profile(path,old)
  var loaded=Session.new()
  check(loaded.load_game(path),"load v%d before migration"%version)
  var p:Dictionary=loaded.snapshot()
  check(p.version==7 and p.rebirth==State.zero() and p.player.transmigration==0,"v%d gains no invented history"%version)
  check(p.player.level==33 and p.player.gold==1234567 and p.player.hp==40 and p.player.attack==10,"v%d preserves old stats/assets"%version)
  check(loaded.save_game(path),"v%d migrated save"%version)
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak")) # No fallback may hide invalid v7.
  var again=Session.new()
  var reread:bool=again.load_game(path)
  if not reread:print("LOAD ERROR: "+again.last_error)
  else:
   var actual:Dictionary=again.snapshot()
   for key in p:
    if actual.get(key)!=p[key]:print("READBACK DIFF ",key, " expected=",p[key]," actual=",actual.get(key))
  check(reread and again.snapshot()==p,"v%d migration is idempotent after real readback"%version)
  old.player.transmigration=3;write_profile(path,old);loaded=Session.new()
  check(loaded.load_game(path) and loaded.snapshot().rebirth.history=="legacy_unknown" and not loaded.snapshot().rebirth.has("equation"),"v%d positive old count preserved without invented Q/L"%version)
  check(not State.continuation_error(loaded.snapshot()).is_empty() and loaded.snapshot().player.transmigration==3,"unknown history blocks only new rebirth v%d"%version)
  var unknown:Dictionary=loaded.snapshot()
  check(loaded.save_game(path),"unknown history v%d saves without invented fields"%version)
  DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
  again=Session.new()
  check(again.load_game(path) and again.snapshot()==unknown,"unknown history v%d exact disk readback"%version)
  var hybrid:Dictionary=old.duplicate(true);hybrid.rebirth={"schema":1}
  check(not s._valid_profile(hybrid),"v%d rejects future partial rebirth group"%version)
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 for key in State.FIELDS:
  var broken:Dictionary=fresh.duplicate(true);broken.rebirth.erase(key)
  check(not s._valid_profile(broken),"half-group rejected: "+key)
 var unknown_count:Dictionary=legacy(6);unknown_count.player.transmigration=33;State.migrate(unknown_count);unknown_count.version=7
 check(s._valid_profile(unknown_count) and unknown_count.rebirth.history=="legacy_unknown" and unknown_count.player.transmigration==33,"old positive count above supported natural five is preserved, not clamped")
 var c:=candidate(s)
 check(s._valid_profile(c),"natural fixed base and round budget validate")
 for changed in ["equation","round_points","count","base","fraction","nan","points"]:
  var bad:Dictionary=c.duplicate(true)
  match changed:
   "equation":bad.rebirth.equation=79
   "round_points":bad.rebirth.round_points=20
   "count":bad.rebirth.count=1
   "base":bad.player.base_stats.vitality+=1
   "fraction":bad.rebirth.equation=1.5
   "nan":bad.rebirth.equation=NAN
   "points":bad.player.stat_points=999
  check(not s._valid_profile(bad),"inconsistent natural history rejected: "+changed)
 var before:Dictionary=s.snapshot();var disk:="user://rebirth-atomic-foundation.json"
 write_profile(disk,before)
 check(not s.commit_transmigration_candidate(c,"user://missing-rebirth-dir/save.json") and s.snapshot()==before,"failed candidate write restores all in-memory fields")
 check(s.commit_transmigration_candidate(c,disk),"validated candidate single atomic write succeeds")
 var restored=Session.new()
 check(restored.load_game(disk) and restored.snapshot().rebirth==c.rebirth,"transaction and fixed inheritance survive readback")
 check(not s.commit_transmigration_candidate(c,disk),"same persisted round cannot be committed twice")
 check(restored.allocate_stat("strength",10) and restored.snapshot().player.stat_points==0 and restored._valid_profile(restored.snapshot()),"round ten points allocate independently of inherited fixed base")
 check(restored.gm_set_base_stat(-1,"strength",30) and restored._valid_profile(restored.snapshot()) and restored.snapshot().rebirth.developer_base_delta.strength!=0,"explicit developer change has separate delta ledger")
 check(restored.gm_grant_points(2) and restored.snapshot().player.stat_points==2 and restored._valid_profile(restored.snapshot()),"new-round GM points remain separate")
 var b=Backend.new();var unchanged:Dictionary=b.session.snapshot()
 var king:="777/ten.arg@32021:31:28"
 check(not b.original_quests.npc_by_id(king).is_empty(),"production descriptor exposes reviewed king after approved activation")
 for command in [{"type":"transmigration","action":"preview","npc_id":king,"pet_ids":[]},{"type":"transmigration","action":"confirm","token":"fake"},{"type":"transmigration","action":"cancel","token":"fake"}]:
  var rejected:Dictionary=b.handle(command)
  var expected:="请沿原路线走到精灵王身边。" if command.action=="preview" else "转生确认已过期，请重新与精灵王交谈。"
  check(not rejected.ok and rejected.get("reason")==expected and b.session.snapshot()==unchanged and b.transmigration.pending.is_empty(),"enabled service rejects unauthorized request without mutation: "+str(command.action))
 # Explicit closed-descriptor fixture: remove only this module's directory
 # tags from this isolated catalog. Do not revert production activation.
 b.quest_catalog.enabled_events=b.quest_catalog.enabled_events.filter(func(event):return int(event) not in [48,49,50,51,52])
 check(b.original_quests.npc_by_id(king).is_empty(),"closed fixture projects no king service")
 for action in ["preview","confirm","cancel"]:
  var result:Dictionary=b.handle({"type":"transmigration","action":action,"token":"fake","enabled":true,"count":5})
  check(not result.ok and str(result.reason).contains("尚未开放") and b.session.snapshot()==unchanged,"explicit closed fixture rejects client activation: "+action)
 b.free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(disk+suffix))
 print("TRANSMIGRATION MIGRATION: %d failures"%failures)
 quit(1 if failures else 0)
