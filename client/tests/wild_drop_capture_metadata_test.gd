extends "res://tests/clear_capture_test.gd"
func run()->void:
 var b=backend_for();var found:=troop_for(b)
 check(not found.is_empty(),"actual source troop for capture")
 if found.is_empty():b.free();quit(1);return
 var slot:=int(found.slot);var config:Dictionary=b.session.start_wild_battle_config(found.troop,slot)
 check(config.enemies.all(func(e):return e.has("generated_drop_slots")),"source sidecars exist only in encounter actors")
 var settings:Dictionary=b.automation.profile_settings();settings.preset="capture";settings.capture_fallback_rate=0;settings.capture_fallback_attempts=30
 var trial:=run_core(config,settings,slot,43)
 check(bool(trial.state.enemies[slot].captured) and b.session.apply_battle_result(trial.state),"real strategy and Session capture succeed")
 var pet:Dictionary=b.session.snapshot().pets.back()
 check(not pet.has("generated_drops") and not pet.has("generated_drop_slots") and int(pet.growth_seed)==int(found.troop.enemies[slot].growth_seed),"captured pet preserves original growth but no temporary drop metadata")
 var path:="user://wild-drop-capture-metadata.json"
 check(b.session.save_game(path),"captured profile saves")
 var copy=preload("res://server/game_session.gd").new()
 var loaded:bool=copy.load_game(path)
 check(loaded,"captured save read-back succeeds: "+copy.last_error)
 if loaded:
  var restored:Dictionary=copy.snapshot().pets.back()
  for key in ["species","name","level","growth_seed","base_stats","growth_weights","pet_id","max_hp","attack","defence","speed"]:
   check(restored.get(key)==pet.get(key),"capture read-back preserves "+key)
  check(not restored.has("generated_drops") and not restored.has("generated_drop_slots"),"capture read-back contains no temporary drop metadata")
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path));b.queue_free()
 print("WILD DROP CAPTURE METADATA: %d failures"%failures);quit(1 if failures else 0)
