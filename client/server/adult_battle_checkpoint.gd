extends RefCounted
## Only event4's solo original 10204 encounter. No party or generic battle resume.
const Session=preload("res://server/game_session.gd")
const Battle=preload("res://server/battle_session.gd")
const ENEMIES=[450,451,452,453]
static func snapshot(b) -> Dictionary:
 if not b.automation.resume_wanted() or b.quest_auto.quest_id!=1 or b.quest_auto.resume_state().is_empty() or not b.battle_open or b.party_battle() or b.session._pending.is_empty():return {}
 var pending:Dictionary=b.session._pending
 var live:Dictionary=b.battle.snapshot()
 if not live.get("active",false) or not pending.get("allies",[]).is_empty() or pending.get("enemies",[]).is_empty():return {}
 for enemy in pending.enemies:
  if int(enemy.get("source_enemy_id",-1)) not in ENEMIES:return {}
 return {"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y],"version":1,"battle_id":str(pending.battle_id),"turn":int(live.turn),"profile":b.session.snapshot(),"pending":pending.duplicate(true),"state":live,"rng_state":b.battle._rng.state,"rng_seed":b.battle.rng_seed,"escape_attempts":b.battle._escape_attempts,"skill_used":b.battle._skill_used,"chosen_skill":b.battle._chosen_skill,"pet_target":b.battle._pet_target,"encounter_rng_state":b.encounter_rng.state,"pressure":b.encounter_catalog.pressure,"encounter_serial":b.encounter_serial}
static func restore(b,saved:Dictionary) -> bool:
 if int(saved.get("version",0))!=1 or b.battle_open or not b.session._pending.is_empty():return false
 var profile=saved.get("profile")
 var pending=saved.get("pending")
 var live=saved.get("state")
 if not profile is Dictionary or not b.session._valid_profile(profile) or not pending is Dictionary or not live is Dictionary:return false
 var restored_profile:Dictionary=b.session._normalize_numbers(profile)
 if int(restored_profile.version)<6:
  # Match v5 save migration: ignore unauthoritative instance/equipment fields.
  for key in ["original_instances","original_equipment","next_original_uid"]:restored_profile.erase(key)
  Session.OriginalEquipment.migrate(restored_profile)
  restored_profile.version=Session.SAVE_VERSION
 for pet in restored_profile.pets+restored_profile.get("pet_storage",[]):
  if not pet.has("original_end_event"):pet.original_end_event=Session.original_pet_event(pet)
 if not b.session._valid_profile(restored_profile):return false
 var current:Dictionary=b.session.snapshot()
 var id:=str(saved.get("battle_id",""))
 if id.is_empty() or id in current.completed_battles or id in profile.completed_battles or id!=str(pending.get("battle_id","")) or id!=str(live.get("battle_id","")):return false
 if str(profile.character_id)!=str(current.character_id) or str(profile.profile_id)!=str(current.profile_id) or int(profile.next_battle)<int(current.next_battle):return false
 if pending.get("party",false) or not pending.get("allies",[]).is_empty() or not live.get("active",false):return false
 var enemies:Array=pending.get("enemies",[])
 if enemies.is_empty() or enemies.size()>10 or enemies.size()!=live.get("enemies",[]).size():return false
 for index in range(enemies.size()):
  var enemy:Dictionary=enemies[index]
  var actor:Dictionary=live.enemies[index]
  var source_id:=int(enemy.get("source_enemy_id",-1))
  if source_id not in ENEMIES or not b.session._actor_valid(enemy) or not Session._generated_drops_valid(enemy):return false
  var source:Dictionary=b.encounter_catalog.data.get("enemies",{}).get(str(source_id),{})
  if source.is_empty() or str(enemy.species)!="original_"+str(int(source.template_id)) or int(enemy.level)<int(source.get("level_min",20)) or int(enemy.level)>int(source.get("level_max",30)):return false
  if not enemy.get("generated_drops",[]).is_empty():return false # These ordinary drops remain inactive.
  if actor.get("species")!=enemy.species or not Session._original_integer(actor.get("hp"),0,int(enemy.max_hp)):return false
 if not Session._original_integer(live.get("turn"),0,10000) or int(live.turn)!=int(saved.get("turn",-1)):return false
 if int(saved.get("map_id",-1))!=10204 or not saved.get("cell") is Array or saved.cell.size()!=2:return false
 var map_data:Dictionary=preload("res://scripts/map_file.gd").load_map(b.quest_helper.places.file(10204))
 var cell:=Vector2i(saved.cell[0],saved.cell[1])
 if map_data.is_empty() or not b.quest_helper.safe(map_data,cell,{},b.quest_helper.places.links(10204)):return false
 b.automation.position_map=10204
 b.automation.position_cell=Vector2i(saved.cell[0],saved.cell[1])
 b.session._profile=restored_profile
 b.session._pending=pending.duplicate(true)
 b.battle=Battle.new()
 b.battle.rng_seed=int(saved.get("rng_seed",42))
 b.battle.start_battle(pending)
 b.battle._state=live.duplicate(true)
 b.battle._rng.state=int(saved.get("rng_state",b.battle._rng.state))
 b.battle._escape_attempts=int(saved.get("escape_attempts",0))
 b.battle._skill_used=bool(saved.get("skill_used",false))
 b.battle._chosen_skill=int(saved.get("chosen_skill",0))
 b.battle._pet_target=int(saved.get("pet_target",-1))
 b.encounter_rng.state=int(saved.get("encounter_rng_state",b.encounter_rng.state))
 b.encounter_catalog.pressure=int(saved.get("pressure",0))
 b.encounter_serial=int(saved.get("encounter_serial",b.encounter_serial))
 b.battle_state=b.battle.snapshot()
 b.battle_open=true
 b.publish()
 return true
