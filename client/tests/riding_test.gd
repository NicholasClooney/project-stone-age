extends SceneTree
const Riding = preload("res://scripts/riding.gd")
const Actor = preload("res://scripts/legacy_actor.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
class PreviewWorld extends Node2D:
	var data: Dictionary = {"characters":{},"images":{}}
	var textures: Dictionary = {}
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error("FAIL: "+label)
		failures += 1
	else: print("PASS: "+label)
func _initialize() -> void:
	var pet := {"sprite":100330,"hp":30,"level":1,"loyalty":100}
	var profile := {"character_id":"100010","player":{"level":1},"pets":[pet],"active_pet":-1}
	check(Riding.composite("100010",100330) == 101006,"source gold tiger rider maps to native101006")
	check(Riding.composite("100000",100330) == -1,"unsupported rider is never fabricated")
	check(Riding.can_mount(profile,0).is_empty(),"compatible healthy loyal pet can mount")
	profile.active_pet = 0
	check(not Riding.can_mount(profile,0).is_empty(),"battle pet cannot simultaneously be riding pet")
	profile.active_pet = -1
	pet.loyalty = 99
	check(not Riding.can_mount(profile,0).is_empty(),"riding requires source loyalty100")
	pet.loyalty = 100
	pet.hp = 0
	check(not Riding.can_mount(profile,0).is_empty(),"unconscious pet cannot mount")
	pet.hp = 30
	pet.level = 7
	check(Riding.can_mount(profile,0).is_empty(),"project convenience allows mounts above player level plus five")
	pet.level = 140
	check(Riding.can_mount(profile,0).is_empty(),"mount has no owner level gap bound")
	profile.player.riding_level = 139
	check(not Riding.can_mount(profile,0).is_empty(),"learned riding level is enforced when supplied")
	profile.player.riding_level = 140
	check(Riding.can_mount(profile,0).is_empty(),"mount at learned riding level remains allowed")
	var stats := Riding.adjusted_stats({"attack":10,"defence":10,"speed":10},{"attack":20,"defence":20,"speed":20})
	check(is_equal_approx(stats.attack,24) and is_equal_approx(stats.defence,21) and is_equal_approx(stats.speed,15),"classic melee riding uses native80/70/50percent blends")
	check(is_equal_approx(Riding.adjusted_stats({"speed":10},{"speed":20},"reference").speed,18),"reference riding attack agility20/80")
	check(is_equal_approx(Riding.adjusted_stats({"speed":10},{"speed":20},"classic",true).speed,19),"riding defensive agility10/90")
	check(Riding.experience(20,1,1) == 12 and Riding.experience(20,10,1) == 8,"riding XP applies original60percent and overlevel penalty")
	var authority = preload("res://server/battle_session.gd").new()
	var mount := {"sprite":100330,"hp":100,"max_hp":100,"attack":20,"defence":20,"speed":20}
	var initial: Dictionary = authority.start_battle({"player_hp":100,"player_max_hp":100,"player_attack":10,"player_defence":10,"player_speed":10,"pets":[mount],"active_pet":-1,"ride_pet_index":0,"ride_pet":mount,"mounted_sprite":101006})
	check(authority.submit_action("switch",0,0) == initial,"riding pet cannot be deployed into battle slot")
	check(is_equal_approx(authority._player_stats().attack,24),"authority applies riding attack blend exactly once")
	authority._apply_player_damage(20)
	var damaged: Dictionary = authority.snapshot()
	check(damaged.player_hp == 86 and damaged.pets[0].hp == 93,"source mounted damage splits14rider7mount with native rounding")
	authority._state.pets[0].hp = 1
	authority._apply_player_damage(3)
	check(authority.snapshot().ride_pet == -1 and authority.snapshot().mounted_sprite == -1,"mount reaching zeroHP automatically dismounts")
	check(is_equal_approx(authority._player_stats().attack,10),"dismount removes riding stat benefits")
	call_deferred("render_native")
func render_native() -> void:
	var scene := PreviewWorld.new()
	root.add_child(scene)
	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2.ZERO,Vector2(1280,0),Vector2(1280,800),Vector2(0,800)])
	bg.color = Color("335c37")
	scene.add_child(bg)
	for facing in [1,3,5,7]:
		var actor := Actor.new()
		actor.world = scene
		actor.mounted_character_id = "101006"
		actor.facing = facing
		actor.position = Vector2(140+((facing-1)/2)*240,300)
		scene.add_child(actor)
		actor.set_action(4)
		actor._process(0.2)
		check(actor.sprite.texture != null,"native gold tiger walking bitmap loads direction"+str(facing))
		check(PaletteSheet.is_palette(actor.sprite.texture) and actor.sprite.material==PaletteSheet.material_of(actor.sprite.texture),"the rider draws from its palette sheet, facing "+str(facing))
		check(actor.sprite.position.y < 0,"native mounted foot anchor preserved")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/original-gold-tiger-riding.png")
	scene.queue_free()
	await process_frame
	await process_frame
	print("Riding failures: ",failures)
	quit(1 if failures else 0)
