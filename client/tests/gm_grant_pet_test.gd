extends SceneTree
## GM 调试 发放宠物: a Lv1 pet of any original template with imported battle
## art, born by the same rules as a caught Lv1 pet, marked as a GM change.
const Game = preload("res://server/game_session.gd")
const Backend = preload("res://server/backend.gd")
const Growth = preload("res://server/progression.gd")
const Riding = preload("res://scripts/riding.gd")
const SpecialPets = preload("res://scripts/special_pets.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func click(control: BaseButton) -> void:
	control.pressed.emit()

func run() -> void:
	rules()
	backend_command()
	await menu()
	print("GM GRANT PET: %d failures" % failures)
	quit(1 if failures else 0)

func rules() -> void:
	var game = Game.new()
	var template: Dictionary = Growth.species_definition("original_304")
	check(game.gm_grant_pet(304,true),"机暴 (original 304) is granted")
	var pet: Dictionary = game.snapshot().pets[-1]
	check(pet.species=="original_304" and int(pet.template_id)==304 and int(pet.sprite)==100374 and pet.name=="帖拉所伊朵" and int(pet.level)==1,"as a Lv1 帖拉所伊朵 with its template and sprite")
	check(not str(pet.get("pet_id","")).is_empty(),"with a stable pet id")
	var full: Array = template.weights.map(func(w): return int(w)+2)
	check(pet.growth_weights==full,"满档 fixes all four birth grades at +2")
	var initial := 0
	for key in Growth.STATS:initial += int(pet.base_stats[key])
	check(initial==(int(full[0])+int(full[1])+int(full[2])+int(full[3])+10)*int(template.initial),"birth stats are the grades plus 10 points times the template's initial value, like a caught Lv1 pet")
	check(int(pet.growth_rank)==0,"its growth bracket follows the species' weight sum (104: bracket 0)")
	check(not pet.get("gm_modified",false) and not game.snapshot().get("gm_modified",false),"a granted pet is an ordinary birth: neither it nor the profile is marked as a GM change")
	check(game.gm_grant_pet(302),"蓝暴 with random grades")
	var random: Array = game.snapshot().pets[-1].growth_weights
	var base302: Array = Growth.species_definition("original_302").weights
	var within := true
	for i in range(4):within = within and absi(int(random[i])-int(base302[i]))<=2
	check(within,"random grades stay within -2..+2 of the template")
	var before: Dictionary = game.snapshot()
	check(not game.gm_grant_pet(0) and not game.gm_grant_pet("304") and not game.gm_grant_pet(INF) and not game.gm_grant_pet(99998),"invalid or unknown templates are refused")
	var missing := -1
	var templates: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/encounters/catalog.json")).templates
	for id in templates:
		if not SpecialPets.unavailable_reason(int(id)).is_empty():
			missing = int(id)
			break
	if missing > 0:
		check(not game.gm_grant_pet(missing) and game.last_error.contains("战斗图未导入"),"a template without imported battle art is refused (%d)" % missing)
	check(not game.gm_grant_pet(10417) and game.last_error.contains("没有原版数值"),"a later album pet with art but no original stats (巴雅, 10417) is refused")
	check(game.snapshot()==before,"a refusal changes nothing")
	# A pet no map spawns, whose art lives in its own file (BattleArt extra sprite).
	var extra_template := 1177
	check(preload("res://scripts/battle_art.gd").is_extra(int(templates[str(extra_template)].sprite)),"布里萨尔's sprite is kept in its own file")
	check(game.gm_grant_pet(extra_template) and game.snapshot().pets[-1].name=="布里萨尔","and it can be granted like the special pets")
	game._profile.pets.pop_back()
	for entry in SpecialPets.LIST:
		check(SpecialPets.unavailable_reason(int(entry[0])).is_empty(),"%s can be granted" % entry[1])
	# Rideable like any owned pet once the rules allow it.
	var index: int = game.snapshot().pets.size()-2
	if Riding.composite("100000",100374) > 0:
		game.select_pet(index+1)
		check(game.mount_pet(index),"the granted 机暴 can be ridden")
		game.mount_pet(index)
	# Full party: the warehouse takes it.
	while game.snapshot().pets.size() < Game.PET_CAPACITY:game.gm_grant_pet(5)
	var stored: int = game.snapshot().pet_storage.size()
	check(game.gm_grant_pet(901) and game.snapshot().pets.size()==Game.PET_CAPACITY and game.snapshot().pet_storage.size()==stored+1 and game.snapshot().pet_storage[-1].name=="葛雷基欧","with a full party the pet goes to the warehouse")
	var path := "user://gm-grant-pet-test.json"
	check(game.save_game(path),"the save with granted pets passes validation")
	var loaded = Game.new()
	check(loaded.load_game(path) and loaded.snapshot().pets[0].species=="original_304","and loads again")
	check(loaded.gm_raise_level(0,120) and int(loaded.snapshot().pets[0].level)==120,"a granted pet levels with normal growth")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
	# Locked during a battle, like every GM change.
	var battle_game = Game.new()
	battle_game._pending = {"battle_id":"x"}
	check(not battle_game.gm_grant_pet(304) and battle_game.snapshot().pets.is_empty(),"granting is locked during a battle")

func backend_command() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	var reply: Dictionary = backend.handle({"type":"gm_grant_pet","template":968,"full_grade":true})
	check(reply.ok and backend.session.snapshot().pets[-1].name=="艾迪希洛","the backend command grants 机豹 (a remote client sends the same)")
	check(not backend.handle({"type":"gm_grant_pet"}).ok,"a command without a template is refused")
	check(not backend.handle({"type":"gm_grant_pet","template":-3}).ok,"and one with a bad template")
	backend.queue_free()

func menu() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	var gm = game.dev_gm_menu
	gm.open_menu()
	await process_frame
	var picker: OptionButton = gm.find_child("GmPetPicker",true,false)
	check(picker!=null and picker.item_count==SpecialPets.LIST.size(),"GM 调试 lists the special pets")
	picker.select(4)
	picker.item_selected.emit(4)
	check(int(gm.template_input.value)==812,"choosing 金暴 fills its template id")
	gm.full_grade.button_pressed = true
	var count: int = game.session.snapshot().pets.size()
	click(gm.grant_button)
	await process_frame
	check(game.session.snapshot().pets.size()==count+1 and game.session.snapshot().pets[-1].name=="斑尼迪克","发放 adds 斑尼迪克 to the party")
	check(gm.feedback.text.contains("斑尼迪克") and gm.feedback.text.contains("满档") and gm.feedback.text.contains("随身"),"and says what was granted and where")
	check(gm.actor_picker.item_count==count+2,"the GM actor list includes the new pet")
	gm.template_input.value = 99998
	click(gm.grant_button)
	check(game.session.snapshot().pets.size()==count+1 and gm.feedback.text.contains("99998"),"an unknown id shows the refusal")
	gm.close_menu()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await create_timer(0.3).timeout
