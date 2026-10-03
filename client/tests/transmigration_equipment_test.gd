extends SceneTree
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Effects=preload("res://scripts/original_item_effects.gd")
const Rules=preload("res://server/original_quests.gd")
const Backend=preload("res://server/backend.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
 if not ok:failures+=1;push_error(note)
 else:print("PASS: "+note)
func write(path:String,data:Dictionary)->void:
 var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func add(s,id:int)->int:
 Equipment.add(s._profile,id);return int(s.snapshot().original_instances[-1].uid)
func equip(s,uid:int)->bool:return s.equip_item("original:%d"%uid)
func run()->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-equipment.json"))
 check(fixture.records.size()==142,"exact142 added fixed ordinary definitions")
 var session=Session.new();session.gm_raise_level(-1,100);var clean:Dictionary=session.snapshot()
 for record in fixture.records:
  session._profile=clean.duplicate(true)
  var id:=int(record.id);var d:Dictionary=Equipment.ITEMS.get(id,{})
  check(d.size()==record.definition.size() and d.keys().all(func(key):return str(d[key])==str(record.definition[key]) if key in ["name","slot"] else int(d[key])==int(record.definition[key])),"source-equal full ordinary definition %d"%id)
  var uid:=add(session,id)
  check(equip(session,uid) and int(session.snapshot().original_equipment[d.slot])==uid,"source equipment worn into exact existing slot %d"%id)
  var mods:Dictionary=session.equipment_mods()
  check(Equipment.STATS.all(func(stat):return int(mods[stat])==int(d[stat])),"four fixed ordinary fields active %d"%id)
  check(Equipment.valid(session.snapshot()),"UID/slot/durability valid %d"%id)
  for effect in Effects.resolve(record.item):
   var supported:bool=str(effect.type)=="stat" and str(effect.get("stat","")) in Equipment.STATS
   check(bool(effect.active)==supported,"effect boundary %d %s"%[id,effect.label])
  if int(d.durability)==0:
   Equipment.settle(session._profile,Equipment.battle_items(session._profile))
   check(session.snapshot().original_instances.size()==1 and Equipment.stage(session.snapshot().original_instances[0])==0,"source zero-durability item survives settlement %d"%id)
  if int(d.level)>0:
   session._profile=clean.duplicate(true);var low_uid:=add(session,id);session._profile.player.level=maxi(1,int(d.level)-1)
   check(not equip(session,low_uid),"one below source level refuses %d"%id)
 # Five slots coexist; both BODY systems replace each other without deleting UID.
 var s=Session.new();s.gm_raise_level(-1,100)
 var uids:Array=[]
 for id in [33,874,1034,2694,1269]:uids.append(add(s,id));check(equip(s,uids[-1]),"representative five slots")
 check(s.snapshot().original_equipment.values().all(func(uid):return int(uid)>0),"all five source slots coexist")
 s._profile.inventory.haru_armor=1
 check(s.equip_item("haru_armor") and int(s.snapshot().original_equipment.body)==0,"legacy BODY replaces new original BODY")
 check(equip(s,uids[2]) and str(s.snapshot().equipment.body).is_empty(),"new BODY replaces legacy BODY")
 var forged:Dictionary=s.snapshot();forged.equipment.body="haru_armor"
 check(not Equipment.valid(forged),"dual BODY forged state rejected")
 # Core spirit rings and carried source items use the existing amulet slot.
 for id in [2699,2700,2701,2706,2707,2766,2770]:
  var item_session=Session.new();item_session.gm_raise_level(-1,100);var uid:=add(item_session,id)
  check(Rules.matches(item_session.snapshot(),"ITEM=%d"%id),"source item visible in bag %d"%id)
  check(equip(item_session,uid) and not Rules.matches(item_session.snapshot(),"ITEM=%d"%id),"worn source item cannot satisfy bare task condition %d"%id)
  check(not Rules.worn_item_hint(item_session.snapshot(),"ITEM=%d"%id).is_empty(),"worn source item receives unequip hint %d"%id)
  check(equip(item_session,uid) and Rules.matches(item_session.snapshot(),"ITEM=%d"%id),"unequip restores task eligibility %d"%id)
 migration(fixture)
 var b=Backend.new();b.session.gm_raise_level(-1,100);var uid:=add(b.session,2770)
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-spirit-equipment/fail.json"
 check(not b.handle({"type":"equip_item","item":"original:%d"%uid}).ok and b.session.snapshot()==before,"equip save failure rolls back UID slot and complete profile")
 b.save_path="user://spirit-equipment-saved.json"
 check(b.handle({"type":"equip_item","item":"original:%d"%uid}).ok,"equip retry saves")
 var restored=Session.new();check(restored.load_game(b.save_path) and restored.snapshot().original_instances==b.session.snapshot().original_instances and restored.snapshot().original_equipment==b.session.snapshot().original_equipment,"real save reload preserves UID durability and slot")
 b.free()
 print("TRANSMIGRATION EQUIPMENT: %d failures"%failures);quit(1 if failures else 0)
func migration(fixture:Dictionary)->void:
 var s=Session.new();s.gm_raise_level(-1,100);var clean:Dictionary=s.snapshot()
 var loaded=Session.new();var again=Session.new()
 for record in fixture.records:
  s._profile=clean.duplicate(true)
  var uid:=add(s,int(record.id));var legacy:Dictionary=s.snapshot()
  legacy.original_instances[0].durability=0;var next_uid:int=legacy.next_original_uid
  check(Equipment.valid(legacy),"old metadata passes pre-migration validation %d"%int(record.id))
  Equipment.migrate(legacy)
  check(legacy.original_instances[0].uid==uid and legacy.next_original_uid==next_uid and legacy.original_instances[0].durability==record.definition.durability,"local migration preserves identity and source durability %d"%int(record.id))
  if int(record.definition.durability)>0:
   legacy.original_instances[0].durability=1;Equipment.migrate(legacy)
   check(legacy.original_instances[0].durability==1,"repeat migration never repairs damaged new equipment")
  if int(record.id) in [33,874,1034,2694,1269,2701,2707,2770,2699]:
   legacy.original_instances[0].durability=0
   write("user://spirit-equipment-migration.json",legacy)
   check(loaded.load_game("user://spirit-equipment-migration.json") and loaded.snapshot().original_instances[0].durability==record.definition.durability,"real old metadata file loads %d"%int(record.id))
   if int(record.definition.durability)>0:loaded._profile.original_instances[0].durability=1
   var expected:Dictionary=loaded.snapshot()
   check(loaded.save_game("user://spirit-equipment-migration.json"),"migrated state saves")
   check(again.load_game("user://spirit-equipment-migration.json") and again.snapshot().original_instances==expected.original_instances,"second disk load preserves migrated and damaged state")
 for id in [1052,1357]:
  s._profile=clean.duplicate(true);add(s,id);s._profile.original_instances[0].durability=1
  Equipment.migrate(s._profile);check(s.snapshot().original_instances[0].durability==1,"existing equipment never refilled %d"%id)
