extends "res://tests/original_drops_test.gd"
func run()->void:
 var catalog=Catalog.new();var rng:=RandomNumberGenerator.new()
 var trusted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 check(trusted.reviewed_drops.has("transmigration-water") and trusted.reviewed_drops["transmigration-water"].active,"production water drops enabled")
 var ids:Array=[]
 for d in trusted.reviewed_drops["transmigration-water"].entries:
  if not int(d.enemy_id) in ids:ids.append(int(d.enemy_id))
 ids.sort();check(ids==[1324,1334,1335,1336,1347,1348,1349],"exact water drop enemy whitelist")
 var disabled:Dictionary=trusted.duplicate(true);disabled.reviewed_drops["transmigration-water"].active=false
 Catalog.configure_reviewed_drops(disabled)
 for id in ids:check(not Catalog.drop_enemy_allowed(id),"disabled water does not leak drops %d"%id)
 Catalog.configure_reviewed_drops(trusted)
 check(catalog.roll_drops(catalog.data.enemies["1324"],rng_for(799))==[2767],"water stone800 includes799")
 check(catalog.roll_drops(catalog.data.enemies["1324"],rng_for(800)).is_empty(),"water stone800 excludes800")
 for enemy in ids:
  var expected:int=2767 if enemy==1324 else (1249 if enemy<1340 else 1238)
  var seen_shell:=false;var seen_other:=false
  for seed_value in range(10000):
   rng.seed=seed_value;var drops:Array=catalog.actor(enemy,rng).generated_drops
   seen_shell=seen_shell or 2766 in drops;seen_other=seen_other or expected in drops
   if seen_other and (enemy==1324 or seen_shell):break
  check(seen_other and (enemy==1324 or seen_shell),"all original slots active, companion loot preserved %d"%enemy)
 var actor:Dictionary={}
 for seed_value in range(10000):
  rng.seed=seed_value;actor=catalog.actor(1334,rng)
  if 2766 in actor.generated_drops:break
 check(2766 in actor.generated_drops,"deterministic original shell roll found")
 var b=backend();b.open_battle(b.session.start_wild_battle_config({"enemies":[actor]}))
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-water-drop/fail.json"
 finish(b)
 check(b.session.snapshot()==before and not b.session._pending.is_empty(),"shell save failure preserves profile and original rolled loot")
 b.save_path="";check(b.handle({"type":"battle_close"}).ok,"same shell roll retries")
 check(b.session.snapshot().original_items.count(2766)==1,"one shell UID after retry")
 var saved:Dictionary=b.session.snapshot();b.handle({"type":"battle_close"})
 check(b.session.snapshot()==saved,"replayed battle close cannot duplicate shell")
 b.queue_free();print("TRANSMIGRATION WATER DROPS: %d failures"%failures);quit(1 if failures else 0)
