extends SceneTree
const BattleArt = preload("res://scripts/battle_art.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
## Battle sounds follow the original client: every committed command plays SE
## 203 (battlemenu.cpp BattleTargetSelect:3207, BattleButtonGuard:1253), so a
## turn with a pet beeps twice; every attacker that deals damage plays the hit
## SE its attack clip's marker selects (oft.cpp play_damage via 6986-6996),
## mounted or not; frame SE ids are all mapped (tools/import_battle_sounds.py).
var failures := 0
var sounds: Array[int] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok: failures += 1

func settle(view: Control) -> void:
	view._process(maxf(0.0,view.feedback_until-view.elapsed)+0.01)

func run() -> void:
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	view.sound_requested.connect(func(ident: int): sounds.append(ident))
	await process_frame
	view.set_process(false)
	view.battle_effects.set_process(false)

	# Selection: character command, then pet command, each confirmed once.
	var authority = load("res://server/battle_session.gd").new()
	var rex := {"name":"巴朵兰恩","sprite":100373,"hp":300,"max_hp":300,"attack":200,"defence":50,"speed":80,"level":60}
	var state: Dictionary = authority.start_battle({"player_hp":100,"player_max_hp":100,"player_attack":10,"player_defence":10,"player_speed":10,"enemy_max_hp":100000,"enemy_attack":1,"pets":[rex],"active_pet":0})
	view.open_battle(state)
	settle(view)
	sounds.clear()
	view._request_action("attack")
	check(sounds==[217],"choosing 攻击 plays the menu click 217")
	view.select_target(1)
	check(sounds.count(203)==1 and view.command_phase=="pet","the character's target confirms with 203 and the pet's command follows")
	settle(view)
	check(view.selected_action=="pet_attack","the pet's remembered 攻击 is ready for a target")
	view.select_target(1)
	check(sounds.count(203)==2,"the pet's target confirms with 203 too: two beeps per turn (嘟嘟)")

	# Pet commands without a target confirm as well.
	view.open_battle(state)
	settle(view)
	view.complete_player_command("defend")
	settle(view)
	sounds.clear()
	view.finish_pet_command("defend")
	check(sounds==[203],"a pet 防御 confirms with 203")

	# 红暴龙's attack: its clip has only hit markers, and the hit sound plays unmounted.
	view.open_battle(state)
	for i in range(240): view._process(1.0/60.0)
	check(str(view.actors[2].character_id)=="100373","the battle shows 红暴龙 as the active pet")
	var impact: int = view.impact_sound(2)
	check(impact in [250,254],"红暴龙's attack marker selects an original hit sound (%d)" % impact)
	check(view.manifest.get("frame_sounds",{}).has(str(impact)),"that hit sound is imported for battles")
	sounds.clear()
	view.pending_action = "attack"
	view.show_state(authority.submit_action("attack"))
	for i in range(600):
		view._process(1.0/60.0)
		view.battle_effects._process(1.0/60.0)
	check(sounds.has(impact),"红暴龙 attacking unmounted plays its hit sound")

	# Every frame sound the imported sprites use is mapped, unless the original table lacks it.
	var manifest: Dictionary = view.manifest
	var unmapped: Array = manifest.get("provenance",{}).get("frame_sounds_unmapped",[])
	var missing: Array = []
	for sprite in manifest.sprites:
		for clip in BattleArt.animations(sprite).values():
			for i in range(SpriteArt.frame_count(clip)):
				var sound := SpriteArt.sound(clip,i)
				if sound>0 and sound<10000 and not manifest.frame_sounds.has(str(sound)) and not unmapped.has(sound) and not missing.has(sound):missing.append(sound)
	check(missing.is_empty(),"every battle frame sound id is mapped to an original SE (missing %s)" % str(missing))
	check(manifest.frame_sounds.has("62") and manifest.frame_sounds.has("63") and manifest.frame_sounds.has("252") and manifest.frame_sounds.has("254"),"swing (62, 63) and hit (252, 254) sounds no longer need the riding manifest")

	view.queue_free()
	await process_frame
	await process_frame
	print("Battle sounds failures: ",failures)
	quit(1 if failures else 0)
