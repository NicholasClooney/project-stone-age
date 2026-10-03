extends "res://tests/original_drops_test.gd"
func run()->void:
 var trusted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var original:Dictionary=trusted.duplicate(true)
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-drops.json"))
 trusted.reviewed_drops["transmigration-test"]={"active":true,"entries":fixture.entries}
 Catalog.configure_reviewed_drops(trusted)
 var catalog=Catalog.new();var rng:=RandomNumberGenerator.new();rng.seed=39
 var area:Dictionary=catalog.area_at(21002,Vector2i(10,10))
 check(int(area.id)==436,"original diary-conditioned earth area436")
 check(catalog.roll_group(area,605,rng,[2698]).is_empty(),"original group605 excludes diary2698")
 var encounter:Dictionary=catalog.roll_group(area,605,rng,[])
 check(not encounter.is_empty() and encounter.enemies.any(func(e):return int(e.source_enemy_id)==1146),"without diary original feather encounter remains available")
 check(catalog.roll_drops(catalog.data.enemies["1146"],rng_for(999))==[2700],"earth feather original probability1000")
 check(catalog.roll_drops(catalog.data.enemies["1324"],rng_for(799))==[2767],"water stone probability800 includes799")
 check(catalog.roll_drops(catalog.data.enemies["1324"],rng_for(800)).is_empty(),"water stone probability800 excludes800")
 var b=backend();var actor:Dictionary=catalog.actor(1146,rng)
 var config:Dictionary=b.session.start_wild_battle_config({"enemies":[actor]})
 check(not config.is_empty(),"real session accepts original feather enemy")
 b.open_battle(config)
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-transmigration-drops/fail.json"
 finish(b)
 check(b.session.snapshot()==before and not b.session._pending.is_empty(),"drop save failure retains roll and restores profile")
 b.save_path=""
 check(b.handle({"type":"battle_close"}).ok,"same original drop result retries")
 check(b.session.snapshot().original_items.count(2700)==1,"source feather delivered exactly once")
 var saved:Dictionary=b.session.snapshot();b.handle({"type":"battle_close"})
 check(b.session.snapshot()==saved,"repeated battle close cannot duplicate feather")
 b.queue_free();Catalog.configure_reviewed_drops(original)
 print("TRANSMIGRATION DROPS: %d failures"%failures)
 quit(1 if failures else 0)
