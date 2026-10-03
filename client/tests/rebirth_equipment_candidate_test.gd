extends SceneTree
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func fixture(bag:int)->Dictionary:
 var s=Session.new();s.gm_raise_level(-1,80)
 for key in s._profile.inventory:s._profile.inventory[key]=0
 for id in [2418,1052,33,2694,1269]:
  Equipment.add(s._profile,id)
  var entry:Dictionary=s._profile.original_instances[-1]
  if int(entry.durability)>0:entry.durability=17
  s._profile.original_equipment[Equipment.ITEMS[id].slot]=entry.uid
 for i in bag:Equipment.add(s._profile,2767)
 return s._profile.duplicate(true)
func run()->void:
 for count in [0,1,5,33]:
  var original:Dictionary=fixture(15);original.player.level=1;original.player.transmigration=count
  var before:Dictionary=original.duplicate(true)
  var result:Dictionary=Equipment.revalidate_after_transmigration(original)
  check(original==before,"candidate input never mutated count"+str(count))
  if count>0:
   check(result.ok and result.profile==before and result.unequipped_uids.is_empty(),"five legal slots retain exact UID/wear/full bag including unknown legacy positive count"+str(count))
   check(Equipment.valid(result.profile) and Session.bag_slots(result.profile)==15,"same unified legality and exact15 bag semantics count"+str(count))
  else:check(not result.ok and not result.has("profile"),"all five illegal underlevel removals reject atomically when bag would overflow")
 var candidate:Dictionary=fixture(10);candidate.player.level=1;candidate.player.transmigration=0
 var before:Dictionary=candidate.duplicate(true)
 var result:Dictionary=Equipment.revalidate_after_transmigration(candidate)
 check(result.ok and result.unequipped_uids.size()==5 and Session.bag_slots(result.profile)==15,"illegal-slot reconciliation uses net capacity for all five removals")
 check(candidate==before and result.profile.original_instances==before.original_instances and result.profile.original_items==before.original_items and result.profile.next_original_uid==before.next_original_uid,"unwearing never removes or repairs instances, changes UID counter, or mutates input")
 check(result.profile.original_equipment.values().all(func(uid):return int(uid)==0),"all five invalid slots are empty only in accepted candidate")
 result.profile.original_instances[0].durability=1
 check(candidate==before,"returned nested profile is isolated from candidate")
 var positive:Dictionary=fixture(15);positive.player.level=1;positive.player.transmigration=1
 var invalid:Dictionary=positive.duplicate(true);invalid.original_equipment.head=invalid.original_equipment.body
 check(not Equipment.revalidate_after_transmigration(invalid).ok,"cross-slot duplicate UID rejects rather than being silently unshipped")
 invalid=positive.duplicate(true);invalid.equipment.body="haru_armor";invalid.inventory.haru_armor=1
 check(not Equipment.revalidate_after_transmigration(invalid).ok,"BODY1052 and counted legacy BODY exclusivity remains")
 invalid=positive.duplicate(true);invalid.original_instances[0].durability=0
 check(not Equipment.revalidate_after_transmigration(invalid).ok,"zero worn durability rejects and is not repaired by migration")
 invalid=positive.duplicate(true);invalid.player.transmigration=1.5
 check(not Equipment.revalidate_after_transmigration(invalid).ok,"fractional count rejects rather than acting like known positive history")
 for slot in ["body","amulet"]:
  var legacy:Dictionary=fixture(0)
  legacy.original_equipment[slot]=0
  var name:String="haru_armor" if slot=="body" else "koyala_charm"
  legacy.inventory[name]=1;legacy.equipment[slot]=name
  legacy.player.level=1;legacy.player.transmigration=1
  var retained:Dictionary=Equipment.revalidate_after_transmigration(legacy)
  check(retained.ok and retained.profile==legacy,"counted legacy "+slot+" remains equipped without new UID")
 var legacy_zero:Dictionary=fixture(14);legacy_zero.original_equipment.body=0
 legacy_zero.equipment.body="haru_armor";legacy_zero.inventory.haru_armor=1
 legacy_zero.player.level=1;legacy_zero.player.transmigration=0
 var legacy_before:Dictionary=legacy_zero.duplicate(true)
 check(not Equipment.revalidate_after_transmigration(legacy_zero).ok and legacy_zero==legacy_before,"counted legacy illegal removal also rejects net overflow atomically")
 var flags:Dictionary=fixture(0);flags.original_equipment.arm=0;flags.original_equipment.amulet=0
 flags.equipped=true;flags.equipped_mirror=true;flags.inventory.club=1;flags.inventory.mirror_charm=1
 flags.player.level=1;flags.player.transmigration=1
 check(Equipment.revalidate_after_transmigration(flags).profile==flags,"legacy club and mirror flags preserve existing ownership")
 var medicine:Dictionary=fixture(0);Equipment.add(medicine,2450)
 medicine.player.level=1;medicine.player.transmigration=1
 var entry:Dictionary=medicine.original_instances[-1].duplicate(true)
 var unchanged:Dictionary=Equipment.revalidate_after_transmigration(medicine)
 check(unchanged.ok and unchanged.profile.original_instances[-1]==entry,"2450 remains exact one-UID revival item outside equipment scan")
 print("REBIRTH EQUIPMENT CANDIDATE: %d failures"%failures);quit(1 if failures else 0)
