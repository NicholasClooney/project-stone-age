extends SceneTree
const Session=preload("res://server/game_session.gd")
const Battle=preload("res://server/battle_session.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func old_positive(count:int):
 var s=Session.new();s._profile.version=6;s._profile.erase("rebirth");s._profile.player.transmigration=count
 Session.TransmigrationState.migrate(s._profile);s._profile.version=Session.SAVE_VERSION
 return s
func _initialize()->void:
 var s=old_positive(1)
 check(s._valid_profile(s.snapshot()) and s._profile.rebirth.history=="legacy_unknown","known old positive count needs no invented history for peripheral rules")
 Session.OriginalEquipment.add(s._profile,1052)
 var uid:int=s._profile.original_instances[0].uid
 s._profile.original_instances[0].durability=1234
 check(s.equip_item("original:%d"%uid) and s._valid_profile(s.snapshot()),"Lv1 positive count equips actual high-level BODY1052")
 check(s._profile.original_instances[0].uid==uid and s._profile.original_instances[0].durability==1234,"equip keeps actual UID and wear")
 s._profile.inventory.freya_robe=1
 check(s.equip_item("freya_robe") and s._profile.original_equipment.body==0,"legacy body uses same positive-count exemption and keeps exclusivity")
 var zero=Session.new();Session.OriginalEquipment.add(zero._profile,1052)
 check(not zero.equip_item("original:%d"%int(zero._profile.original_instances[0].uid)),"zero-count Lv1 still rejects original equipment")
 zero._profile.inventory.freya_robe=1
 check(not zero.equip_item("freya_robe"),"zero-count Lv1 still rejects legacy spirit")
 for count in [1,5]:
  var owner=old_positive(count)
  var config:Dictionary=owner.start_battle_config("wooli",false,1)
  config.player_defence=1000;config.player_speed=1000;config.capture_bonus=200
  for enemy in config.enemies:enemy.hp=1
  var battle=Battle.new();battle.start_battle(config);battle.submit_action("capture",0)
  var result:Dictionary=battle.snapshot()
  check(result.outcome=="captured" and owner.apply_battle_result(result),"real Session capture settles for positive count "+str(count))
  if owner._profile.pets.is_empty():continue
  var caught:Dictionary=owner.snapshot().pets[0]
  check(caught.modai==150 and caught.variable_ai==-4000 and caught.loyalty==73,"capture uses original capped debt then normal work loyalty, count "+str(count))
  var debt:int=caught.variable_ai
  check(owner.store_pet(0),"caught pet stores")
  var stored:Dictionary=owner.snapshot().pet_storage[0]
  check(stored.variable_ai==debt and stored.loyalty==73,"warehouse refresh keeps debt and same owner compensation")
  var path:="user://rebirth-peripheral-session-%d.json"%count
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
  check(owner.save_game(path),"positive owner and pet save")
  var reader=Session.new()
  check(reader.load_game(path) and reader.snapshot().pet_storage[0].variable_ai==debt and reader.snapshot().pet_storage[0].loyalty==73,"loaded owner count refresh preserves original VARIABLEAI")
  check(reader.retrieve_pet(0),"retrieve preserved pet")
  # Admission uses the same snapshot loyalty; no second battle-side bonus.
  reader.select_pet(0)
  var live:Dictionary=reader.start_battle_config("wooli",false,1)
  check(live.pet.loyalty==73 and live.pets[0].variable_ai==debt,"battle admission sees exactly one owner bonus")
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("REBIRTH SESSION RULES: %d failures"%failures)
 quit(1 if failures else 0)
