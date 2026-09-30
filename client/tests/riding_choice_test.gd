extends SceneTree
## Every imported ridePetTable mount: backend rules, the pet window's ride
## button and a mounted battle with a mount other than the gold tiger.
const Riding = preload("res://scripts/riding.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")

## Starter pets re-dressed as 格鲁西斯 (100329), rideable by appearance 100000,
## and gold tiger (100330), which only other appearances ride.
func prepare(session) -> void:
	session.grant_starter_pets()
	session.set_character("100000")
	session._profile.pets[0].sprite = 100329
	session._profile.pets[0].name = "格鲁西斯"
	session._profile.pets[1].sprite = 100330
	session._profile.pets[1].name = "金虎"
	for pet in session._profile.pets:pet.loyalty = 100

## Every frame of a composite is cut from its sprite sheet at the frame's size.
func sheet_frames() -> void:
	var sheeted := true
	for composite in Riding.index().get("composites",{}):
		if Riding.read(composite).get("files",PackedStringArray()).is_empty():sheeted = false
	check(sheeted and Riding.index().get("composites",{}).size() > 19,"every composite has a sprite sheet")
	for composite in ["101004","101009"]:
		var complete := true
		var art := Riding.art(composite)
		for animation in art.animations.values():
			for i in range(SpriteArt.frame_count(animation)):
				var bitmap := SpriteArt.image(animation,i)
				var texture := Riding.frame_texture(composite,bitmap)
				if not texture is AtlasTexture or Vector2i(texture.get_size())!=SpriteArt.image_size(art,bitmap) or texture.get_image().is_invisible():complete = false
		check(complete,"composite %s draws every frame from its sheet" % composite)
	check(Riding.frame_texture("101004",-5)==null,"a frame the sheet lacks draws nothing instead of failing")

func run() -> void:
	check(Riding.index().get("pairs",{}).size() > 19,"importer provides more than the gold tiger and brontosaurus pairs")
	check(Riding.composite("100000",100329) == 101004 and Riding.composite("100020",100396) == 101010,"ridePetTable pairs for other mounts resolve")
	var rideable := Riding.rideable_pets("100000")
	check([100329,100352,100372,100373,100369,100370,100904].all(func(pet): return rideable.has(pet)),"appearance 100000 rides its two ridePetTable mounts and the certificate mounts the 2.5 pack draws")
	# RideNoList gives 左迪洛斯 / 巴朵兰恩 the character's family-leader composite; no client has another.
	check(Riding.composite("100010",100373) == 101009 and Riding.composite("100035",100372) == 101018,"red rex and 左迪洛斯 use the character's leader mounted sprite")
	check(int(Riding.pair("100010",100373).get("leader_body",0)) == 100705,"the leader art is recorded")
	check(Riding.pet_name(100329) == "格鲁西斯","mount names come from the source enemy templates")
	sheet_frames()
	backend_rules()
	certificate_mounts()
	await menu_button()
	await mounted_battle()
	print("Riding choice failures: ",failures)
	quit(1 if failures else 0)

func backend_rules() -> void:
	var session = preload("res://server/game_session.gd").new()
	prepare(session)
	check(not session.mount_pet(1),"pet without a composite for this character is rejected")
	check(session.last_error.contains("可骑乘") and session.last_error.contains("格鲁西斯") and session.last_error.contains("布林帖斯"),"rejection names the pets this character can ride")
	check(session.mount_pet(0) and int(session.snapshot().ride_pet) == 0,"rideable source mount is accepted")
	check(not session.mount_pet(2) and session.last_error.contains("下骑"),"a second mount needs a dismount first")
	check(session.mount_pet(-1) and int(session.snapshot().ride_pet) == -1,"dismount")
	session._profile.pets[0].loyalty = 99
	check(not session.mount_pet(0) and session.last_error.contains("忠诚"),"loyalty 100 required")
	session._profile.pets[0].loyalty = 100
	session._profile.pets[0].level = 7
	check(not session.mount_pet(0) and session.last_error.contains("5"),"player level + 5 bound")
	session._profile.pets[0].level = 1
	session.select_pet(0)
	check(not session.mount_pet(0) and session.last_error.contains("出战"),"battling pet cannot be ridden")
	session.select_pet(-1)
	check(session.mount_pet(0),"mount again after standby")
	session.set_character("100010")
	check(int(session.snapshot().ride_pet) == -1,"changing to an appearance without that composite dismounts")
	# The starter 红暴龙 (巴朵兰恩) is rideable by any appearance.
	var rex := -1
	for i in range(session._profile.pets.size()):
		if int(session._profile.pets[i].sprite) == 100373:rex = i
	check(rex >= 0,"the starter pets include 红暴龙")
	session._profile.pets[rex].loyalty = 100
	session._profile.pets[rex].level = 1
	check(session.mount_pet(rex) and int(session.snapshot().ride_pet) == rex,"红暴龙 can be ridden")
	check(Riding.composite(str(session.snapshot().character_id),100373) == 101009,"riding 红暴龙 draws this character's leader mounted sprite")
	session.mount_pet(-1)

## _NEW_RIDEPETS mounts: RideNoList[character][RideCodeMode index] composites.
func certificate_mounts() -> void:
	check(not Riding.REQUIRE_RIDING_CERTIFICATES,"riding certificates are not required (documented decision)")
	check(int(Riding.pair("100000",100288).get("certificate",-1)) == 4,"扬奇洛斯 records its certificate RIDE_PET4")
	var has_8_0: bool = not Riding.index().get("extra_source",{}).get("composites",[]).is_empty()
	if not has_8_0:
		var missing := false
		for pair in Riding.index().get("unavailable",[]):
			if int(pair.pet) == 100288 and str(pair.reason).contains("--extra-source"):missing = true
		check(Riding.composite("100000",100288) < 0 and missing,"without the 8.0 data 扬奇洛斯 is listed as unavailable")
		print("SKIP: 8.0 certificate composites not imported (setup without --no-8.0)")
		return
	check(Riding.composite("100000",100288) == 101309 and Riding.composite("100005",100288) == 101309,"扬奇洛斯 draws character 0's composite for its colour variants")
	check(Riding.composite("100035",100288) == 101317 and Riding.composite("100235",100374) == 101393,"other characters draw their own 扬奇洛斯 / 帖拉所伊朵 composite")
	check(Riding.composite("100000",101532) == 101978 and Riding.composite("100000",101576) == 101989,"史卡鲁 and 罗多克雷 use the 1019xx composites")
	check(Riding.art("101309").get("animations",{}).has("0_3"),"the certificate composite includes battle actions")
	check(Riding.pet_name(100288) == "扬奇洛斯" and Riding.pet_name(100370) == "奇宝","certificate mount names come from the enemy templates")
	check(Riding.composite("100000",100373) == 101009,"红暴龙 keeps the leader composite: 8.0 has no normal-outfit one either")
	var session = preload("res://server/game_session.gd").new()
	prepare(session)
	session._profile.pets[1].sprite = 100288
	session._profile.pets[1].name = "扬奇洛斯"
	session._profile.pets[1].level = 1
	check(session.mount_pet(1) and int(session.snapshot().ride_pet) == 1,"扬奇洛斯 can be ridden without a certificate")
	session.mount_pet(-1)
	session._profile.pets[1].loyalty = 99
	check(not session.mount_pet(1) and session.last_error.contains("忠诚"),"certificate mounts keep the loyalty rule")
	session._profile.pets[1].loyalty = 100
	session._profile.pets[1].level = 7
	check(not session.mount_pet(1) and session.last_error.contains("5"),"certificate mounts keep the level rule")
	session._profile.pets[1].level = 1
	session.set_character("100020")
	check(session.mount_pet(1) and Riding.composite(str(session.snapshot().character_id),100288) == 101313+4,"another character rides it with its own composite")
	var config: Dictionary = session.start_battle_config("wooli",false,1)
	check(int(config.mounted_sprite) == 101317,"the battle draws this appearance's 扬奇洛斯 composite")

func menu_button() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.profile_persistence = false
	root.add_child(world)
	await process_frame
	world.muted = true
	prepare(world.session)
	world.show_adventure_menu("pets")
	var menu = world.adventure_menu
	menu.selected_pet = 1
	menu.rebuild()
	var button: Button = menu.panel.find_child("PetMount",true,false)
	var reason = menu.panel.find_child("PetMountReason",true,false)
	check(button != null and button.disabled and button.text.contains("金虎"),"ride button is disabled for a pet this character cannot ride")
	check(reason != null and reason.text.contains("格鲁西斯"),"disabled ride button explains why")
	menu.selected_pet = 0
	menu.rebuild()
	button = menu.panel.find_child("PetMount",true,false)
	check(not button.disabled and button.text.begins_with("骑乘"),"ride button enabled for a rideable pet")
	button.pressed.emit()
	await process_frame
	check(int(world.session.snapshot().ride_pet) == 0,"ride button mounts the selected pet")
	check(str(world.player.mounted_character_id) == "101004","walking art switches to the native composite")
	button = menu.panel.find_child("PetMount",true,false)
	check(button.text.begins_with("下骑") and not button.disabled,"ride button offers dismount for the ridden pet")
	button.pressed.emit()
	await process_frame
	check(int(world.session.snapshot().ride_pet) == -1 and str(world.player.mounted_character_id) == "","dismount from the pet window")
	world.close_adventure_menu()
	world.dev_toggle_riding()
	check(int(world.session.snapshot().ride_pet) == 0,"DEV riding picks the first pet this character can ride")
	world.dev_toggle_riding()
	check(int(world.session.snapshot().ride_pet) == -1,"DEV riding toggles back off")
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await process_frame

func mounted_battle() -> void:
	var session = preload("res://server/game_session.gd").new()
	prepare(session)
	session.mount_pet(0)
	var config: Dictionary = session.start_battle_config("wooli",false,1)
	check(int(config.mounted_sprite) == 101004,"battle config carries the new mount's composite")
	config.player_attack = 10000
	config.player_speed = 10000
	var authority = preload("res://server/battle_session.gd").new()
	var state: Dictionary = authority.start_battle(config)
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.battle_effects.set_process(false)
	view.open_battle(state)
	for i in range(120): view._process(1.0/60.0)
	check(str(view.actors[0].character_id) == "101004","battle draws the native 格鲁西斯 rider composite")
	check(view.actors[0].animations.has("0_3") and view.riding_hp_bar.visible,"mounted actor has attack art and mount health")
	var result: Dictionary = authority.submit_action("attack")
	view.show_state(result)
	check(result.outcome == "win" and session.apply_battle_result(result),"mounted battle settles")
	check(int(session.snapshot().pets[0].xp) > 0 and int(session.snapshot().ride_pet) == 0,"new mount earns riding experience and stays mounted")
	view.queue_free()
	await process_frame
