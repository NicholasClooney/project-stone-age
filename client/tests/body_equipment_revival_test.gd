extends "res://tests/original_wood_equipment_test.gd"
const Revival=preload("res://server/original_revival.gd")
func run() -> void:
 body_rules()
 revival_rules()
 await atomic_equipment()
 print("BODY EQUIPMENT REVIVAL: %d failures" % failures)
 quit(1 if failures else 0)
func body_rules() -> void:
 var s=strong(29);var uid:=add(s,1052)
 check(not equip(s,uid),"BODY source Lv30 enforced")
 s.gm_raise_level(-1,30)
 check(equip(s,uid),"BODY equipment admitted")
 check(s.equipment_mods().defence==20 and s.equipment_mods().speed==-6,"BODY exact ordinary modifiers")
 s._profile.inventory.haru_armor=1
 check(s.equip_item("haru_armor") and s.snapshot().original_equipment.body==0,"legacy BODY replaces original without deleting ownership")
 check(equip(s,uid) and s.snapshot().equipment.body=="","original BODY replaces legacy")
 var saved:Dictionary=s.snapshot()
 var legacy:Dictionary=saved.duplicate(true);legacy.original_equipment.erase("body");legacy.original_instances[0].durability=0
 write("user://body-old.json",legacy)
 var load=Session.new()
 check(load.load_game("user://body-old.json") and load.snapshot().original_instances[0].durability==2500000 and load.snapshot().original_equipment.body==0,"old metadata BODY migrates once and stays unworn")
 saved.original_instances[0].durability=1
 write("user://body-worn.json",saved)
 check(load.load_game("user://body-worn.json") and load.snapshot().original_instances[0].durability==1,"damaged worn BODY survives disk without repair")
 var forged:Dictionary=saved.duplicate(true);forged.player.level=1
 check(not Equipment.valid(forged),"underlevel worn BODY migration rejected")
 forged=saved.duplicate(true);forged.player=17
 check(not Equipment.valid(forged),"malformed wearer rejected without migration script error")
 forged=saved.duplicate(true);forged.original_equipment.head=uid
 check(not Equipment.valid(forged),"same UID cannot occupy HEAD and BODY")
 forged=saved.duplicate(true);forged.equipment.body="haru_armor"
 check(not Equipment.valid(forged),"double original/legacy BODY rejected")
 forged=saved.duplicate(true);forged.original_instances[0].durability=0
 check(not Equipment.valid(forged),"zero worn BODY rejected before migration")
 var ownership:Dictionary=s.snapshot()
 while Session.bag_slots(s.snapshot())<15:add(s,100)
 var full:Dictionary=s.snapshot()
 check(not equip(s,uid) and s.snapshot()==full,"full bag refuses BODY unequip atomically")
 s._profile=ownership
 s._profile.original_instances[0].durability=1
 var cfg:Dictionary=s.start_battle_config();var b=Battle.new();b.start_battle(cfg)
 for i in range(30):
  if not b.snapshot().active or b.snapshot().original_equipment_items[0].durability==0:break
  b.submit_action("defend")
 check(b.snapshot().original_equipment_items[0].durability==0 and not b.snapshot().equipment_occupied[1],"actual received attacks exhaust BODY and clear occupied slot")
 check(int(b._config.player_defence)==int(s._profile.player.defence),"destroyed BODY strips ordinary defence immediately")
 check(s.apply_battle_result(b.developer_escape()) and s.snapshot().original_equipment.body==0 and not 1052 in s.snapshot().original_items,"settlement removes exact exhausted BODY instance")
 remove_files("user://body-old.json");remove_files("user://body-worn.json")
func revival_rules() -> void:
 var s=strong(30);var uid:=add(s,2450)
 check(not s.use_item("original_2450"),"field use rejected without consumption")
 var cfg:Dictionary=s.start_battle_config();var b=Battle.new();b.start_battle(cfg)
 var before:Dictionary=b.snapshot()
 check(b.submit_action("revival:99999",0).turn==before.turn,"forged UID does not advance turn")
 check(b.submit_action("revival:%d"%uid,99).turn==before.turn,"out of range target does not consume")
 check(b.submit_action("revival:%d"%uid,2).turn==before.turn,"absent ally rejected")
 b._state.enemies[0].captured=true
 check(b.submit_action("revival:%d"%uid,10).turn==before.turn,"captured enemy no longer eligible")
 b._state.enemies[0].captured=false
 b._state.player_hp=0
 check(b.submit_action("revival:%d"%uid,0).turn==before.turn,"dead caster cannot self revive")
 b._state.player_hp=before.player_hp
 var result:Dictionary=b.submit_action("revival:%d"%uid,0)
 check(result.turn==1 and result.original_revival_items.is_empty(),"original living target consumes exactly one UID")
 check(b.submit_action("revival:%d"%uid,0).turn==1,"spent UID cannot be replayed")
 b._state.original_revival_items=cfg.original_revival_items.duplicate(true)
 b._state.enemies[0].captured=true
 b._cast_revival({"kind":"player","index":-1},"revival:%d"%uid,{"kind":"enemy","index":0})
 check(b._state.original_revival_items.is_empty(),"valid queued target leaving before execution still consumes per original unconditional delete")
 var rng:=RandomNumberGenerator.new();rng.seed=71
 var minimum:=999;var maximum:=0
 for i in range(5000):
  var hp:=Revival.hp(500,1000,rng);minimum=mini(minimum,hp);maximum=maxi(maximum,hp)
 check(minimum==450 and maximum==550,"source power500 rolls full450..550 range")
 check(Revival.hp(500,80,rng)==80,"revival clamped to target maximum")
 check(not Revival.result_valid(cfg.original_revival_items,[{"uid":uid,"item_id":1532,"durability":0}]),"forged result item ID rejected")
 check(not Revival.result_valid(cfg.original_revival_items,cfg.original_revival_items+cfg.original_revival_items),"duplicate result UID rejected")
func atomic_equipment() -> void:
 var b=Backend.new();root.add_child(b)
 b.session.gm_raise_level(-1,30)
 var uid:=add(b.session,1052)
 var before:Dictionary=b.session.snapshot()
 b.save_path="user://missing-body-dir/save.json"
 var reply:Dictionary=b.handle({"type":"equip_item","item":"original:%d"%uid})
 check(not reply.ok and b.session.snapshot()==before,"equipment save failure rolls whole profile back")
 b.save_path="user://body-equipment-atomic.json"
 reply=b.handle({"type":"equip_item","item":"original:%d"%uid})
 var loaded=Session.new()
 check(reply.ok and loaded.load_game(b.save_path) and loaded.snapshot().original_equipment.body==uid,"equipment success persisted exact worn UID")
 remove_files(b.save_path)
 b.queue_free();await process_frame
