extends "res://tests/original_drops_test.gd"
const Equipment=preload("res://server/original_equipment.gd")
const Storage=preload("res://server/item_storage.gd")
const ENEMIES=[1404,1406,1407,1405,1408,1410,1409,1411,1412,1413]
func actors(catalog)->Array:
 var rng:=RandomNumberGenerator.new()
 for seed_value in range(1000):
  rng.seed=seed_value
  var result:Array=[]
  for id in ENEMIES:result.append(catalog.actor(id,rng))
  if result[3].generated_drops==[2138]:return result
 check(false,"find deterministic original 100/1000 drop seed")
 return []
func open_troop(b)->void:
 # Source formation/loot transaction fixture, not a claim of original-route
 # admission: full natural guard route is tested separately by arrival owner.
 var troop:Array=actors(b.encounter_catalog)
 check(troop.map(func(e):return int(e.source_enemy_id))==ENEMIES,"unchanged original ten-enemy order with fourth drop actor")
 var config:Dictionary=b.session.start_wild_battle_config({"enemies":troop})
 check(not config.is_empty(),"real session accepts original troop and frozen drops")
 b.open_battle(config)
func win_troop(b)->void:
 var state:Dictionary=b.battle.snapshot()
 for i in range(200):
  if not bool(state.active):break
  var target:int=0
  for j in range(state.enemies.size()):
   if int(state.enemies[j].hp)>0:target=j;break
  state=b.battle_command({"action":"attack","target":target})
 check(not bool(state.active) and str(state.get("outcome",""))=="win","actual battle resolves ten-enemy source formation")
func run()->void:
 var trusted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var original:Dictionary=trusted.duplicate(true)
 check(not bool(trusted.reviewed_drops["transmigration-final"].active),"production descriptor does not enable original drop")
 trusted.reviewed_drops["transmigration-final"].active=true
 Catalog.configure_reviewed_drops(trusted)
 var c=Catalog.new()
 check(c.roll_drops(c.data.enemies["1405"],rng_for(99))==[2138],"original100/1000 includes99")
 check(c.roll_drops(c.data.enemies["1405"],rng_for(100)).is_empty(),"original100/1000 excludes100")
 var b=backend()
 # Backend creates another catalog and restores production activation.
 Catalog.configure_reviewed_drops(trusted)
 for stat in ["vitality","toughness","dexterity"]:check(b.session.gm_set_base_stat(-1,stat,10000),"GM battle fixture "+stat)
 check(b.session.gm_heal(),"GM battle fixture restored HP")
 var item:Dictionary=b.quest_catalog.items["2138"]
 check(Storage.reason(item).is_empty(),"original flags allow meat warehouse storage")
 check(item.effects.size()==1 and not bool(item.effects[0].active) and not item.has("use"),"meat recovery explicitly inactive; no use action metadata")
 open_troop(b)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-final-meat/fail.json"
 win_troop(b)
 check(b.session.snapshot()==before and not b.session._pending.is_empty(),"failed drop save rolls back profile and UID retaining frozen pending")
 b.save_path="user://final-meat-saved.json"
 check(b.handle({"type":"battle_close"}).ok,"same frozen drop retries successfully")
 var state:Dictionary=b.session.snapshot()
 check(state.original_items.count(2138)==1,"exactly one original meat instance delivered")
 var uid:int=-1
 for instance in state.original_instances:
  if int(instance.item_id)==2138:uid=int(instance.uid)
 check(uid>0,"drop owns a stable instance UID")
 b.handle({"type":"battle_close"})
 check(b.session.snapshot()==state,"duplicate close never duplicates original loot")
 var cmd:Dictionary={"type":"item_storage_transfer","direction":"deposit","revision":int(state.item_storage_revision),"items":[{"uid":uid}]}
 check(b.handle(cmd).ok,"source-allowed meat deposits through actual storage transaction")
 var copy=Backend.new()
 check(copy.load_profile(b.save_path),"drop/storage actual saved profile loads")
 check(copy.session.snapshot().item_storage==b.session.snapshot().item_storage,"warehouse preserves drop UID on durable reload")
 copy.free();b.queue_free()
 b=backend();Catalog.configure_reviewed_drops(trusted)
 for stat in ["vitality","toughness","dexterity"]:check(b.session.gm_set_base_stat(-1,stat,10000),"GM battle fixture "+stat)
 check(b.session.gm_heal(),"GM battle fixture restored HP")
 while Session.bag_slots(b.session._profile)<15:Equipment.add(b.session._profile,2468)
 var next_uid:int=int(b.session._profile.next_original_uid)
 open_troop(b);win_troop(b)
 check(b.handle({"type":"battle_close"}).ok,"full bag still settles ordinary battle")
 state=b.session.snapshot()
 check(state.original_items.count(2138)==0 and int(state.next_original_uid)==next_uid and Session.bag_slots(state)==15,"full bag neither merges meat nor allocates hidden UID")
 b.queue_free();Catalog.configure_reviewed_drops(original)
 print("TRANSMIGRATION FINAL DROPS: %d failures"%failures)
 quit(1 if failures else 0)
