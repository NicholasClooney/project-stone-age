extends "res://tests/original_wood_equipment_test.gd"
const Revival=preload("res://server/original_revival.gd")
func run() -> void:
 await authority()
 await solo_retry()
 await enemy_cycle()
 check(not Revival.can_revive(0,true,true) and Revival.can_revive(0,false,true),"original PVP rule excludes people but allows pets; no PVP mode added")
 check(not Revival.can_revive(1,false,false),"living targets never gain revival HP")
 print("BODY REVIVAL AUTHORITY: %d failures"%failures)
 quit(1 if failures else 0)
func authority() -> void:
 for owns in [false,true]:
  var b=Backend.new();root.add_child(b)
  if owns:add(b.session,2450)
  var cfg:Dictionary=b.session.start_battle_config()
  var trusted:Array=cfg.original_revival_items.duplicate(true)
  if not owns:b.session._pending.erase("original_revival_items")
  else:b.session._pending.revival_transaction=true
  cfg.original_revival_items=[Equipment.instance(2450,98765)]
  cfg.revival_transaction=false;cfg.pvp=true;cfg.original_revival_budget=99999
  var reply:Dictionary=b.handle({"type":"open_battle","config":cfg})
  check(reply.ok and b.battle.snapshot().original_revival_items==trusted,"open_battle replaces forged medicine list, including absent trusted key")
  check(b.battle._config.get("original_revival_budget",0)==trusted.size(),"client cannot forge pet revival budget")
  check(not b.battle._config.get("pvp",false),"client cannot create PVP mode when trusted config lacks it")
  check(not owns or b.battle._config.revival_transaction,"client cannot cancel trusted transaction")
  var before:Dictionary=b.battle.snapshot()
  var refused:Dictionary=b.handle({"type":"battle_command","action":"revival:98765","target":0,"battle_id":before.battle_id,"turn":before.turn})
  check(not refused.ok and b.battle.snapshot().turn==before.turn,"forged UID rejected at real backend command boundary")
  for target in ["0",{},0.5,-1,20]:
   check(not b.handle({"type":"battle_command","action":"revival:1","target":target}).ok,"malformed or outside target refused without coercion")
  b.handle({"type":"battle_escape_dev"});b.queue_free();await process_frame
func solo_retry() -> void:
 var b=Backend.new();root.add_child(b)
 b.save_path="user://body-revival-solo-%d.json"%OS.get_process_id()
 b.session.gm_raise_level(-1,30);b.session.grant_starter_pets();b.session.select_pet(0)
 var uid:=add(b.session,2450)
 check(b.save(),"solo baseline persisted")
 var cfg:Dictionary=b.session.start_battle_config()
 b.open_battle(cfg)
 b.battle._state.pet_hp=0;b.battle._state.pet.hp=0;b.battle._state.pets[0].hp=0
 var prior:Dictionary=b.session.snapshot()
 var token:Dictionary=b.battle.snapshot()
 var result:Dictionary=b.handle({"type":"battle_command","action":"revival:%d"%uid,"target":1,"battle_id":token.battle_id,"turn":token.turn})
 check(result.ok and b.battle.snapshot().pet_hp>0 and b.battle.snapshot().original_revival_items.is_empty(),"real solo authority revives participating pet using one exact UID")
 var hp:int=b.battle.snapshot().pet_hp
 check(b.battle.snapshot().pets[0].get("original_revival_count",0)==1,"successful pet revival records one source loyalty gain")
 DirAccess.make_dir_absolute(b.save_path+".tmp")
 b.handle({"type":"battle_escape_dev"})
 check(not b.session._pending.is_empty() and b.session.snapshot()==prior,"solo failed save rolls all profile fields back")
 var rng_state:int=b.battle._rng.state
 check(not b.handle({"type":"battle_close"}).ok and b.session.snapshot()==prior,"second solo save failure retains pending and rollback")
 DirAccess.remove_absolute(b.save_path+".tmp")
 check(b.handle({"type":"battle_close"}).ok and b.session._pending.is_empty(),"solo successful retry clears pending")
 check(int(b.session.snapshot().pets[0].variable_ai)==mini(10000,int(prior.pets[0].variable_ai)+300),"pet resurrection applies original variable AI +300 exactly once")
 check(b.battle._rng.state==rng_state and b.session.snapshot().pets[0].hp==hp,"solo retries keep frozen HP and RNG")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and loaded.snapshot().pets[0].hp==hp and loaded.snapshot().original_items.count(2450)==0,"solo disk contains revived pet and one consumed medicine")
 remove_files(b.save_path);b.queue_free();await process_frame

func enemy_cycle() -> void:
 var b=Backend.new();root.add_child(b)
 b.save_path="user://body-revival-enemy-%d.json"%OS.get_process_id()
 b.session.gm_raise_level(-1,30)
 var uid:=add(b.session,2450)
 var before:Dictionary=b.session.snapshot()
 var cfg:Dictionary=b.session.start_battle_config("wooli",false,2)
 for enemy in cfg.enemies:enemy.source_wait_only=true
 cfg.enemies[0].generated_drops=[2401]
 b.session._pending=cfg.duplicate(true)
 b.open_battle(cfg)
 for i in range(50):
  if b.battle.snapshot().enemies[0].hp<=0:break
  b.battle_command({"action":"attack","target":0})
 check(b.battle.snapshot().active and b.battle.snapshot().enemies[0].hp==0,"actual solo attacks kill first enemy while another keeps battle open")
 var identity:String=b.battle.snapshot().enemies[0].battle_uid
 check(b.battle.drop_claims_for()==[{"enemy":0,"item":0}],"first real death generates one cached claim")
 b.battle_command({"action":"revival:%d"%uid,"target":10})
 check(b.battle.snapshot().enemies[0].hp>0 and b.battle.snapshot().enemies[0].battle_uid==identity and b.battle.snapshot().enemies[0].loot_credited,"actual enemy-target resurrection keeps instance identity and loot guard")
 check(b.battle.drop_claims_for().is_empty(),"revived enemy has no payable death claim")
 for i in range(50):
  if b.battle.snapshot().enemies[0].hp<=0:break
  b.battle_command({"action":"attack","target":0})
 check(b.battle.drop_claims_for()==[{"enemy":0,"item":0}],"second actual death restores only original claim")
 for i in range(50):
  if not b.battle.snapshot().active:break
  b.battle_command({"action":"attack","target":1})
 var after:Dictionary=b.session.snapshot()
 check(b.session._pending.is_empty() and b.battle.snapshot().outcome=="win","enemy death-revival-death finishes normal settlement")
 check(after.player.xp-before.player.xp==int(cfg.enemies[0].reward_xp)+int(cfg.enemies[1].reward_xp) and after.player.gold-before.player.gold==int(cfg.enemies[0].reward_gold)+int(cfg.enemies[1].reward_gold),"XP and gold paid once per final enemy instance")
 check(after.original_items.count(2401)==1 and after.original_items.count(2450)==0,"one original drop and exactly one consumed revival after enemy cycle")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and loaded.snapshot().original_items==after.original_items,"enemy-cycle committed inventory reads back")
 b.handle({"type":"battle_close"});b.handle({"type":"battle_close"})
 check(b.session.snapshot()==after,"enemy-cycle final reward cannot replay")
 remove_files(b.save_path);b.queue_free();await process_frame
