extends SceneTree
const Session=preload("res://server/game_session.gd")
const Battle=preload("res://server/battle_session.gd")
const Policy=preload("res://scripts/battle_auto_policy.gd")
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var s=Session.new()
 s.grant_starter_pets();s.select_pet(0)
 var before=s.snapshot()
 check(s.grant_pet_care_items(),"grant healing and mirror items")
 check(not s.grant_pet_care_items(),"grant idempotent")
 check(s.snapshot().inventory.healing_charm==1 and s.snapshot().inventory.mirror_charm==1 and s.snapshot().equipped_mirror,"mirror ready and healing available")
 check(s.snapshot().pets==before.pets and s.snapshot().player==before.player,"grant preserves actors")
 s._profile.pets[0].hp=1;s._profile.pets[1].hp=0
 check(s.heal_carried_pets() and s.snapshot().pets[0].hp==s.snapshot().pets[0].max_hp and s.snapshot().pets[1].hp==0,"field heal caps HP, does not resurrect")
 check(s.save_game("user://pet-healing-test.json"),"new optional inventory saves")
 var loaded=Session.new()
 check(loaded.load_game("user://pet-healing-test.json") and not loaded.grant_pet_care_items(),"grant persists across reload")
 s._profile.pets[0].hp=1
 var config=s.start_battle_config()
 config.player_speed=99999;config.enemy_attack=1;config.enemy_max_hp=100000
 var b=Battle.new();b.start_battle(config)
 var decision=Policy.decide(b.snapshot(),{"preset":"capture"},0)
 check(decision.action=="heal_pet" and decision.pet=="defend","capture automation heals injured pet first")
 b.set_pet_command("defend")
 var state=b.submit_action("heal_pet")
 check(state.turn==1 and state.pet_hp>1 and "恢复护符" in str(state.events),"healing consumes normal player action")
 check(not s.heal_carried_pets(),"field healing blocked during pending battle")
 var forbidden=Battle.new();config.healing_available=false;forbidden.start_battle(config)
 check(forbidden.submit_action("heal_pet").turn==0,"no healing item rejects action")
 var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.session.grant_pet_care_items()
 game.adventure_menu.open_menu("inventory")
 check(game.adventure_menu.item_name("healing_charm")=="恢复护符（辅助）","healing item visible name")
 await process_frame
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
 # Short suites quit before the audio thread drops the stopped playback; give it real time.
 await create_timer(0.3).timeout
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://pet-healing-test.json"))
 print("PET HEALING: %d failures"%failures)
 quit(1 if failures else 0)
