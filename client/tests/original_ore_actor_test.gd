extends "res://tests/fast_hunt_test.gd"
const Session=preload("res://server/game_session.gd")
const Ore=preload("res://server/original_ore_actor.gd")
func run()->void:
 var b=Backend.new();root.add_child(b)
 var original:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 var reviewed:Dictionary=original.duplicate(true)
 reviewed.get_or_add("reviewed_drops",{})["ore-fixture"]={"active":true,"entries":[{"enemy_id":1043,"item_id":2534,"probability":1000}]}
 EncounterCatalog.configure_reviewed_drops(reviewed)
 Session.OriginalEquipment.add(b.session._profile,2536)
 var rng:=RandomNumberGenerator.new();rng.seed=27
 var area:Dictionary=b.encounter_catalog.area_at(31801,Vector2i(24,24))
 var troop:Dictionary=b.encounter_catalog.roll_group(area,508,rng,b.session.snapshot().original_items)
 var ore:Dictionary={}
 for enemy in troop.enemies:
  if int(enemy.source_enemy_id)==1043:ore=enemy
 check(not ore.is_empty() and ore.growth_weights==[98,1,3,-1] and int(ore.base_stats.dexterity)==-250,"original failing seed27 preserves signed raw weights and base")
 if ore.is_empty():b.queue_free();quit(1);return
 ore.xp=0
 var unchanged:Dictionary=ore.duplicate(true)
 check(not b.session._actor_valid(ore) and b.session._wild_actor_valid(ore) and ore==unchanged,"only reviewed wild validation accepts raw negative; actor unchanged")
 check(int(ore.speed)==1 and not ore.can_capture,"existing derived speed minimum1; original ore remains uncapturable")
 for key in ["source_enemy_id","template_id","can_capture"]:
  var fake:=ore.duplicate(true);fake[key]=true if key=="can_capture" else 1042
  check(not b.session._wild_actor_valid(fake),"forged negative ore identity rejected: "+key)
 var fake:=ore.duplicate(true);fake.growth_weights[3]=-3
 check(not b.session._wild_actor_valid(fake),"below original perturbation bound rejected")
 fake=ore.duplicate(true);fake.base_stats.dexterity=-501
 check(not b.session._wild_actor_valid(fake),"off-grid and below source base bound rejected")
 fake=ore.duplicate(true);fake.base_stats.strength+=250
 check(not b.session._wild_actor_valid(fake),"eleven initial extra allocations rejected")
 fake=ore.duplicate(true);fake.speed=2
 check(not b.session._wild_actor_valid(fake),"invented derived values rejected")
 var original_pet:=int(Ore.source.pet_flag);Ore.source.pet_flag=1
 check(not b.session._wild_actor_valid(ore),"trusted source must itself declare uncapturable")
 Ore.source.pet_flag=original_pet
 var bad_profile:Dictionary=b.session.snapshot();bad_profile.player.base_stats.dexterity=-1
 check(not b.session._valid_profile(bad_profile),"negative player save still rejected")
 var pet:=ore.duplicate(true);pet.pet_id="pet-1";pet.xp=0;pet.skill_unlocked=false
 bad_profile=b.session.snapshot();bad_profile.pets=[pet];bad_profile.next_pet_id=2
 check(not b.session._valid_profile(bad_profile),"negative raw ore cannot become saved pet")
 # Lower possible source bounds: -2 perturbation, zero extra on dexterity;
 # put the ten original allocation points into vitality, without changing draws.
 var edge:=ore.duplicate(true);edge.growth_weights=[98,-2,3,-2]
 edge.base_stats={"vitality":108*250,"strength":-2*250,"toughness":3*250,"dexterity":-2*250}
 Progression.refresh(edge);edge.hp=edge.max_hp
 check(b.session._wild_actor_valid(edge),"exact negative source lower bounds are accepted only with ten allocations")
 var boundary_session=Session.new()
 check(not boundary_session.start_wild_battle_config({"enemies":[edge]}).is_empty(),"exact source negative boundary starts a real Session battle")
 boundary_session.cancel_pending_battle(str(boundary_session._pending.battle_id))
 b.session.gm_raise_level(-1,120);check(b.session.gm_set_base_stat(-1,"strength",1000) and b.session.gm_set_base_stat(-1,"toughness",1000) and b.session.gm_set_base_stat(-1,"vitality",1000) and b.session.gm_heal(-1),"real GM prepares valid winning character")
 var config:Dictionary=b.session.start_wild_battle_config(troop)
 check(not config.is_empty(),"unchanged seed27 complete troop accepted by real Session")
 if config.is_empty():b.queue_free();quit(1);return
 b.open_battle(config)
 var before:Dictionary=b.session.snapshot();b.save_path="user://missing-ore-actor/save.json"
 for turn in range(100):
  if not b.battle.snapshot().active:break
  var state:Dictionary=b.battle.snapshot();var target:=0
  for i in range(state.enemies.size()):
   if int(state.enemies[i].hp)>0:target=i;break
  b.handle({"type":"battle_command","action":"attack","target":target})
 check(not b.battle.snapshot().active and b.session.snapshot()==before and not b.session._pending.is_empty(),"real win failed save preserves pending and all profile fields")
 b.save_path="user://ore-actor.json"
 var closed:Dictionary=b.handle({"type":"battle_close"})
 check(closed.ok and b.session.snapshot().original_items.count(2534)==1,"same real win retries one source guaranteed ore")
 before=b.session.snapshot();b.handle({"type":"battle_close"})
 check(b.session.snapshot()==before,"repeated close cannot duplicate ore")
 var loaded=Backend.new()
 check(loaded.load_profile(b.save_path),"normal post-ore profile validates without widening save schema")
 loaded.free()
 var filter:={"template":-1,"level_one":false,"total":-8,"offsets":[],"limit":0,"rate":0,"usable":area_templates(b.encounter_catalog.data,area)}
 var parity:=run_area(b,b.encounter_catalog.data,"original mineral signed weights",31801,Vector2i(24,24),filter,false,1000)
 check(parity.get("different",-1)==0 and int(parity.get("enemies",0))>1000,"ore region1000 rolls preserve every subsequent actor and C/GDScript parity")
 EncounterCatalog.configure_reviewed_drops(original);b.queue_free()
 print("ORIGINAL ORE ACTOR: %d failures"%failures);quit(1 if failures else 0)
