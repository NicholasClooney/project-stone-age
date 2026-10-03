extends "res://tests/original_quests_test.gd"
## Isolate migration from the public NPC catalogue oracle. The original suite's
## rich v1-v4 preservation checks run too, without unrelated quest content.
const Storage=preload("res://server/item_storage.gd")
func write_profile(path: String, profile: Dictionary) -> void:
 var file:=FileAccess.open(path,FileAccess.WRITE)
 file.store_string(JSON.stringify(profile));file.close()
func remove_profile(path: String) -> void:
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
func run() -> void:
 migration()
 var path:="user://item-storage-legacy-%d.json"%OS.get_process_id()
 for version in range(1,7):
  remove_profile(path)
  var source=Session.new()
  var old: Dictionary=source.snapshot()
  old.version=version
  for key in Storage.FIELDS:old.erase(key)
  if version<6:
   for key in ["original_instances","original_equipment","next_original_uid"]:old.erase(key)
  if version<5:
   for key in Session.ORIGINAL_DEFAULT:old.erase(key)
  if version<4:
   old.player.erase("mp");old.equipment.erase("body");old.equipment.erase("amulet")
  if version<3:
   old.erase("pet_storage");old.erase("next_pet_id")
  old.inventory.potion=37;old.player.gold=4321;old.location={"map_id":2000,"x":55,"y":92};old.travel_pass=true
  var frozen: Dictionary=old.duplicate(true)
  check(source._valid_profile(old),"Genuine v%d shape without future warehouse fields validates"%version)
  check(old==frozen,"v%d validation is read-only"%version)
  write_profile(path,old)
  var loaded=Session.new()
  check(loaded.load_game(path),"Fresh reader loads genuine v%d without backup fallback"%version)
  var migrated: Dictionary=loaded.snapshot()
  check(migrated.inventory.potion==37 and migrated.player.gold==4321 and migrated.location==old.location and migrated.travel_pass,"v%d real disk migration preserves non-default contents"%version)
  check(migrated.item_storage.is_empty() and migrated.legacy_item_storage.is_empty() and migrated.item_storage_revision==0,"v%d migrates to empty storage and initial revision"%version)
  check(loaded.save_game(path),"v%d migrated profile writes"%version)
  var reread=Session.new()
  check(reread.load_game(path) and reread.snapshot()==migrated,"v%d migration reads back identically on a fresh reader"%version)
  # Do not interpret mixed generations as a licence to silently drop items.
  if version<6:
   var hybrid: Dictionary=old.duplicate(true)
   hybrid.item_storage=[];hybrid.legacy_item_storage={};hybrid.item_storage_revision=0
   check(not source._valid_profile(hybrid),"v%d with v6 warehouse fields remains rejected"%version)
  for key in Storage.FIELDS:
   var half: Dictionary=old.duplicate(true)
   half[key]=0 if key=="item_storage_revision" else {} if key=="legacy_item_storage" else []
   check(not source._valid_profile(half),"v%d partial warehouse field %s remains rejected"%[version,key])
 remove_profile(path)
 var modern=Session.new()
 var bad: Dictionary=modern.snapshot()
 var entry: Dictionary=Session.OriginalEquipment.instance(2605,1)
 bad.original_items=[2605];bad.original_instances=[entry.duplicate(true)];bad.item_storage=[entry.duplicate(true)];bad.next_original_uid=2
 check(not modern._valid_profile(bad),"Cross-container UID duplication remains rejected")
 write_profile(path,bad)
 check(not Session.new().load_game(path),"Duplicate UID disk save cannot load without a validated backup")
 remove_profile(path)
 print("ITEM STORAGE LEGACY: %d failures"%failures)
 quit(1 if failures else 0)
