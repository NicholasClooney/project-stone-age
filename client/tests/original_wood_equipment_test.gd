extends SceneTree
## Reviewed source values exercised through real sessions, resolvers and a
## real WebSocket game UI. Never touches the live game's user:// directory.
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Backend=preload("res://server/backend.gd")
const Battle=preload("res://server/battle_session.gd")
const Party=preload("res://server/party_battle_session.gd")
const PartyHost=preload("res://server/party_battles.gd")
const Quests=preload("res://server/original_quests.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value: bool, note: String) -> void:
	print(("PASS: " if value else "FAIL: ")+note)
	if not value:failures+=1
func strong(level: int=30):
	var s=Session.new()
	check(s.gm_raise_level(-1,level),"real level setup")
	return s
func add(s, id: int) -> int:
	Equipment.add(s._profile,id)
	return int(s._profile.original_instances.back().uid)
func equip(s, uid: int) -> bool:return s.equip_item("original:%d" % uid)
func write(path: String, value: Dictionary) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(value));f.close()
func remove_files(path: String) -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func run() -> void:
	rules()
	herb()
	saves()
	battle()
	capture()
	party()
	await discard()
	await resume()
	await remote()
	print("ORIGINAL WOOD EQUIPMENT: %d failures" % failures)
	quit(1 if failures else 0)
func rules() -> void:
	var s=strong(24)
	var axe:=add(s,2465)
	var changed:=add(s,2485)
	var bracelet:=add(s,2481)
	var bracelet2:=add(s,2481)
	var broken:=add(s,2484)
	check(not equip(s,axe) and not equip(s,changed),"both original axes require Lv25")
	check(not equip(s,broken),"2484 remains an unequippable story item")
	check(s.gm_raise_level(-1,25) and equip(s,axe),"original axe admitted at Lv25")
	check(s.equipment_mods()=={"attack":35,"defence":-15,"speed":-15,"charm":0},"2465 exact itemset modifiers")
	check(int(s.snapshot().original_instances[0].durability)==0,"2465 no battle wear")
	check(not equip(s,bracelet),"bracelet requires Lv30")
	s._profile.inventory.club=1
	check(s.equip_item("club") and int(s.snapshot().original_equipment.arm)==0,"club replaces ARM axe without deleting it")
	check(equip(s,changed) and not s.snapshot().equipped,"axe replaces club in same ARM slot")
	check(s.equipment_mods().attack==33 and int(s.snapshot().original_instances[1].durability)==300000,"改造斧 +33 and 300000 durability, no invented upgrade")
	check(s.gm_raise_level(-1,30) and equip(s,bracelet),"bracelet admitted at Lv30")
	s._profile.inventory.koyala_charm=1
	check(s.equip_item("koyala_charm"),"bracelet and amulet wear together")
	check(not equip(s,bracelet2) and s.last_error==preload("res://server/spirits.gd").SAME_KIND,"two bracelet instances cannot wear together")
	check(s.equipment_mods().charm==-5 and int(s.snapshot().player.charm)==60 and int(s.effective_player_stats().charm)==55,"equipment charm is derived, never writes base charm")
	check(Session.bag_slots(s.snapshot())==5,"equipped axe, bracelet, amulet excluded from 15-slot bag; spare copies retained")
	var before: Dictionary=s.snapshot()
	Quests.remove_items(s._profile,"2485*1,2481*1")
	check(not 2485 in s.snapshot().original_items and int(s.snapshot().original_equipment.arm)==0 and int(s.snapshot().original_equipment.bracelet)==0,"quest DelItem includes worn instances and synchronously unequips")
	check(s.snapshot().original_items.count(2481)==1,"quantified DelItem leaves the other bracelet copy")
	s._profile=before.duplicate(true)
	# The equipped copy is newer than the spare: script scanning still starts
	# at original equipment slots rather than canonical acquisition order.
	equip(s,bracelet)
	equip(s,bracelet2)
	Quests.remove_items(s._profile,"2481*1")
	check(s.snapshot().original_items.count(2481)==1 and int(s.snapshot().original_equipment.bracelet)==0 and s.snapshot().original_instances.any(func(entry):return int(entry.uid)==bracelet),"DelItem consumes equipped newer duplicate first, retaining older spare")
	s._profile=before.duplicate(true)
	while Session.bag_slots(s.snapshot())<15:add(s,100)
	var full: Dictionary=s.snapshot()
	check(not equip(s,changed) and s.snapshot()==full,"full bag refuses unequip atomically")
	check(not s.equip_item("original:999999") and not s.equip_item("original:bad"),"unknown and malformed instance commands refused")
func herb() -> void:
	var s=strong(9)
	var amulet:=add(s,2427)
	var bracelet:=add(s,2481)
	check(not equip(s,amulet),"2427 requires Lv10")
	check(s.gm_raise_level(-1,10) and equip(s,amulet),"2427 admitted at Lv10")
	check(s.equipment_mods().charm==-1 and int(s.effective_player_stats().charm)==59 and int(s.snapshot().original_instances[0].durability)==2500000,"2427 exact charm-1 and durability2500000")
	check(Equipment.resistances(s.snapshot())==[2,2,2,2,2,2],"2427 preserves six original resistance modifiers as metadata only")
	s._profile.inventory.mirror_charm=1;s._profile.inventory.koyala_charm=1
	check(not s.equip_item("mirror_charm") and not s.equip_item("koyala_charm"),"2427 prevents legacy mirror and amulet equip")
	check(s.gm_raise_level(-1,30) and equip(s,bracelet),"2427 amulet and bracelet occupy separate decorations")
	check(equip(s,amulet) and s.equip_item("mirror_charm") and not equip(s,amulet),"mirror prevents 2427 equip in reverse direction")
	s.equip_item("mirror_charm");s.equip_item("koyala_charm")
	check(not equip(s,amulet),"legacy spirit amulet also prevents 2427 equip in reverse direction")
	s.equip_item("koyala_charm");equip(s,amulet)
	var config: Dictionary=s.start_battle_config()
	check(config.player_resistances==[2,2,2,2,2,2] and int(config.player_charm)==54 and config.equipment_occupied[3] and config.equipment_occupied[4],"2427 real admission carries resistance metadata and both decoration slots; no fake status application")
	var b=Battle.new();b.start_battle(config)
	var state: Dictionary=b.snapshot()
	for i in range(100):
		if not state.active:break
		state=b.submit_action("attack")
	check(s.apply_battle_result(state) and s.snapshot().original_items.has(2427),"2427 follows real battle settlement and instance ownership")
	var path: String="user://herb-equipment-roundtrip.json"
	remove_files(path);check(s.save_game(path),"2427 equipment saves")
	var loaded=Session.new()
	check(loaded.load_game(path) and loaded.snapshot().original_equipment==s.snapshot().original_equipment and loaded.snapshot().original_instances==s.snapshot().original_instances,"2427 per-copy durability and worn reference survive load")
	remove_files(path)

func saves() -> void:
	var s=strong()
	var first:=add(s,2485)
	add(s,2485)
	var hand:=add(s,2481)
	s._profile.original_instances[0].durability=71
	s._profile.original_instances[1].durability=123456
	equip(s,first);equip(s,hand)
	var path: String="user://wood-equipment-roundtrip.json"
	remove_files(path)
	check(s.save_game(path),"instance equipment saves")
	var loaded=Session.new()
	check(loaded.load_game(path) and loaded.snapshot().original_instances==s.snapshot().original_instances and loaded.snapshot().original_equipment==s.snapshot().original_equipment,"duplicate item IDs keep unique UID, per-copy durability and worn references through load")
	check(s.save_game(path),"valid previous save creates real backup")
	var bad: Dictionary=s.snapshot()
	bad.original_instances[1].uid=bad.original_instances[0].uid
	write(path,bad)
	check(loaded.load_game(path) and loaded.snapshot().original_instances==s.snapshot().original_instances,"corrupted duplicate UID falls back to valid backup")
	remove_files(path)
	# Actual v5 shape: legacy equipment ownership is already included in inventory.
	for mirror in [false,true]:
		var old=strong()
		old._profile.inventory.club=2;old.equip_item("club")
		old._profile.inventory.haru_armor=1;old.equip_item("haru_armor")
		old._profile.inventory.mirror_charm=1
		old._profile.inventory.koyala_charm=1
		old.equip_item("mirror_charm" if mirror else "koyala_charm")
		add(old,2465);add(old,2485);add(old,2481)
		var data: Dictionary=old.snapshot()
		data.version=5
		for key in ["original_instances","original_equipment","next_original_uid"]:data.erase(key)
		write(path,data)
		var migrated=Session.new()
		check(migrated.load_game(path),"actual version5 equipment profile migrates")
		var after: Dictionary=migrated.snapshot()
		check(after.inventory==data.inventory and after.equipment==data.equipment and after.equipped==data.equipped and after.equipped_mirror==data.equipped_mirror and after.original_items==data.original_items,"v5 preserves club/mirror/body/amulet and all quantities without gifts")
		check(after.original_instances.size()==3 and after.original_equipment=={"arm":0,"bracelet":0,"amulet":0,"head":0,"body":0} and int(after.original_instances[1].durability)==300000 and int(after.version)==Session.SAVE_VERSION,"v5 original copies initialized once and remain in bag")
		check(migrated.save_game(path) and Session.new().load_game(path),"migrated v6 save valid for next login")
		remove_files(path)
func battle() -> void:
	var s=strong()
	var axe:=add(s,2485);var hand:=add(s,2481)
	equip(s,axe);equip(s,hand)
	s._profile.original_instances[0].durability=1
	var config: Dictionary=s.start_battle_config()
	check(int(config.player_attack)==int(s._profile.player.attack)+41 and int(config.player_charm)==55,"battle admission uses both attack mods and bracelet charm")
	check(config.player_weapon=="axe" and config.original_equipment_items.size()==2,"resolver receives real worn instances and axe weapon type")
	var b=Battle.new();b.start_battle(config)
	var state: Dictionary=b.snapshot()
	for i in range(100):
		if not state.active:break
		state=b.submit_action("attack")
	check(not state.active and int(state.original_equipment_items[0].durability)==0,"real physical attacks exhaust 1-durability modified axe")
	check(b._config.player_attack==s._profile.player.attack+8 and b._config.player_defence==maxi(0,int(s._profile.player.defence)+5) and b._config.player_speed==maxi(1,int(s._profile.player.speed)-5),"breaking recomputes clamped combat stats from base and remaining bracelet")
	var forged: Dictionary=state.duplicate(true)
	forged.original_equipment_items[0].durability=300001
	check(not s.apply_battle_result(forged),"forged increased durability cannot settle")
	check(s.apply_battle_result(state) and not 2485 in s.snapshot().original_items and not 2484 in s.snapshot().original_items and int(s.snapshot().original_equipment.arm)==0,"settlement removes exhausted modified axe, never gives story broken axe")
	var native=strong();var uid:=add(native,2465);equip(native,uid)
	var original_config: Dictionary=native.start_battle_config()
	b=Battle.new();b.start_battle(original_config)
	state=b.snapshot()
	for i in range(100):
		if not state.active:break
		state=b.submit_action("attack")
	check(native.apply_battle_result(state) and native.snapshot().original_items==[2465] and int(native.snapshot().original_equipment.arm)==uid,"original axe survives real combat without wear or transformation")
	var rng:=RandomNumberGenerator.new();rng.seed=91
	for damage in [1,50,89,90,199,200,201,219,220,1000]:
		for arm in [true,false]:
			var c_rng:=RandomNumberGenerator.new();c_rng.state=rng.state
			var low:=int((damage-50)/40) if arm else int((200-damage)/20)
			if (arm and low<=0) or (not arm and low<0):low=1
			var expected:=low+int((float(low)*1.4-float(low)+1.0)*float(c_rng.randi() & 0x7fffffff)/2147483648.0)
			check(Equipment.wear_amount(damage,arm,rng)==expected,"literal C wear boundary %d ARM=%s" % [damage,arm])
func capture() -> void:
	var s=strong()
	var hand:=add(s,2481);equip(s,hand)
	var config: Dictionary=s.start_battle_config()
	var b=Battle.new();b.start_battle(config)
	var enemy: Dictionary=b.snapshot().enemies[0]
	var expected: Dictionary=preload("res://server/capture_rules.gd").evaluate({"level":config.player_level,"speed":config.player_speed,"charm":55,"luck":config.player_luck},enemy)
	var state: Dictionary=b.submit_action("capture")
	check(state.get("capture_evaluation",{})==expected or (state.get("capture_evaluation",{}).get("score",-999)==expected.get("score",-998) and state.capture_evaluation.eligible==expected.eligible),"real capture action evaluates derived bracelet charm55 with effective speed")
	check(int(s.snapshot().player.charm)==60,"capture never writes bracelet penalty into base charm")

func party() -> void:
	var leader=strong();var member=strong()
	var l:=add(leader,2485);var m:=add(member,2485)
	equip(leader,l);equip(member,m)
	leader._profile.original_instances[0].durability=1
	member._profile.original_instances[0].durability=1
	leader.start_battle_config("wooli",false,10)
	var lc: Dictionary=leader.start_party_config("wood-party")
	var mc: Dictionary=member.start_party_config("wood-party",lc.enemies)
	var host=PartyHost.new(null)
	lc.party_members=[host._member_entry({"name":"真实队友","character_id":"100000"},mc)]
	lc.party_slots=[{"name":"队长","character_id":"100000"},{"name":"队友","character_id":"100000"}]
	var b=Party.new();b.start_battle(lc)
	for i in range(100):
		if not b.snapshot().active:break
		b.submit_slot(0,"attack",0);b.submit_slot(1,"attack",0);b.resolve_turn()
	check(int(b.snapshot().original_equipment_items[0].durability)==0 and int(b.snapshot().allies[0].original_equipment_items[0].durability)==0,"party resolver wears leader and member equipment independently")
	check(b.slice_for(0,str(lc.battle_id)).original_equipment_items[0].uid==l and b.slice_for(1,str(mc.battle_id)).original_equipment_items[0].uid==m,"party slices carry each profile's own instance wear")
	check(leader.apply_battle_result(b.slice_for(0,str(lc.battle_id))) and member.apply_battle_result(b.slice_for(1,str(mc.battle_id))) and leader.snapshot().original_items.is_empty() and member.snapshot().original_items.is_empty(),"real party settlements independently remove each exhausted axe")
func discard() -> void:
	var b=Backend.new();root.add_child(b)
	b.session.gm_raise_level(-1,30)
	var first:=add(b.session,2485);var second:=add(b.session,2485)
	b.session._profile.original_instances[0].durability=55
	b.session._profile.original_instances[1].durability=99
	equip(b.session,second)
	var result: Dictionary=b.handle({"type":"quest_discard","item_id":2485,"instance_uid":second})
	check(result.ok and b.session.snapshot().original_instances.size()==1 and int(b.session.snapshot().original_instances[0].uid)==first and int(b.session.snapshot().original_instances[0].durability)==55 and int(b.session.snapshot().original_equipment.arm)==0,"server discards exactly requested worn duplicate; survivor durability retained")
	b.queue_free();await process_frame
func resume() -> void:
	var b=Backend.new();root.add_child(b)
	b.session.gm_raise_level(-1,30)
	var axe:=add(b.session,2485)
	equip(b.session,axe);b.session._profile.original_instances[0].durability=1
	var path: String="user://wood-equipment-resume.json"
	remove_files(path);remove_files(path+".resume.json")
	b.save_path=path;b.resume_path=path+".resume.json"
	check(b.save(),"real equipment profile persists before live wood battle")
	var rng:=RandomNumberGenerator.new();rng.seed=91
	var actor: Dictionary=b.encounter_catalog.actor(563,rng)
	var config: Dictionary=b.session.start_wild_battle_config({"enemies":[actor]})
	b.open_battle(config)
	for i in range(100):
		if not b.battle.snapshot().active or int(b.battle.snapshot().original_equipment_items[0].durability)==0:break
		b.battle_command({"action":"attack","target":0})
	var live: Dictionary=b.battle.snapshot()
	check(live.active and int(live.original_equipment_items[0].durability)==0,"real wood battle checkpoint occurs after modified axe breaks")
	var attack:=int(b.battle._config.player_attack)
	var rolled: Array=live.enemies[0].get("generated_drops",[]).duplicate()
	b.keep_resume_file()
	check(FileAccess.file_exists(b.resume_path),"real periodic resume file includes live worn-instance wear")
	var restored=Backend.new();root.add_child(restored)
	restored.save_path=path;restored.resume_path=b.resume_path
	check(restored.load_profile(path),"real equipment save loads at restart")
	restored.load_resume()
	check(restored.battle_open and int(restored.battle.snapshot().original_equipment_items[0].durability)==0 and int(restored.battle._config.player_attack)==attack and restored.battle._config.player_weapon=="", "resume keeps exhausted axe and recomputes stripped attack/weapon instead of admission equipment")
	check(restored.battle.snapshot().enemies[0].generated_drops==rolled,"equipment resume never rerolls original wood loot")
	var state: Dictionary=restored.battle.snapshot()
	for i in range(500):
		if not state.active:break
		state=restored.battle_command({"action":"attack","target":0})
	check(not state.active and not restored.session.snapshot().original_items.has(2485) and not restored.session.snapshot().original_items.has(2484),"resumed real battle settles destroyed axe once without story broken axe")
	b.queue_free();restored.queue_free();await process_frame
	remove_files(path);remove_files(path+".resume.json")

func click(control: Control) -> void:
	var point:=control.get_global_rect().get_center()
	var move:=InputEventMouseMotion.new();move.position=point;move.global_position=point
	root.push_input(move,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true);await process_frame
func remote() -> void:
	var backend=Backend.new();root.add_child(backend)
	backend.session.gm_raise_level(-1,30)
	var uid:=add(backend.session,2485);add(backend.session,2481);add(backend.session,2484)
	backend.session._profile.original_instances[0].durability=12345
	var server=preload("res://server/ws_server.gd").new(backend,0,"127.0.0.1")
	root.add_child(server);check(server.start()==OK,"real remote equipment server uses port0")
	var script=load("res://scripts/game.gd")
	script.server_url_override="ws://127.0.0.1:%d" % server.port
	var world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
	world.profile_persistence=false;world.viewer_prefs_path="user://wood-equipment-viewer.cfg"
	root.add_child(world)
	check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"remote equipment game connects and settles")
	check(world.backend==null,"remote equipment UI has no backend")
	world.adventure_menu.open_menu("inventory")
	await process_frame
	var menu=world.adventure_menu
	await click(menu.panel.get_node("OriginalItemSlot_0"))
	check(menu.panel.find_child("OriginalEquipmentDetails",true,false).text.contains("12345 / 300000") and menu.panel.find_child("OriginalEquipmentDetails",true,false).text.contains("等级 25"),"real item click shows per-copy durability, requirements and mods")
	await click(menu.panel.get_node("EquipOriginalItem"))
	check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.arm)==uid) and await Wait.settle(self,world),"real remote equip button executes server-owned instance command")
	var count:=0
	for node in menu.panel.get_children():
		if str(node.name).begins_with("ItemSlot_") or str(node.name).begins_with("EmptyItemSlot_"):count+=1
		elif str(node.name).begins_with("OriginalItemSlot_") and node.position.y>159:count+=1
	check(count==15 and menu.panel.get_node("OriginalItemSlot_0").position.y<159,"worn original axe occupies native ARM and leaves exactly15 bag slots")
	await click(menu.panel.get_node("OriginalItemSlot_1"))
	await click(menu.panel.get_node("EquipOriginalItem"))
	check(await Wait.until(self,func():return int(world.session.snapshot().original_equipment.bracelet)>0) and await Wait.settle(self,world),"real remote bracelet equip command settles")
	check(menu.panel.get_node("OriginalItemSlot_1").position==Vector2(60,45),"bracelet uses original ItemBuffer4 center83,68 rather than an invented slot")
	await click(menu.panel.get_node("OriginalItemSlot_2"))
	check(not menu.panel.has_node("EquipOriginalItem"),"broken story axe has no equip button")
	world.close_adventure_menu()
	world.load_area_id(100,Vector2i(637,493));await Wait.settle(self,world)
	check(world.begin_battle(false,1),"remote equipped axe requests real battle")
	check(await Wait.until(self,func():return world.battle_view.visible and backend.battle_open),"remote axe battle view opens")
	check(world.battle_view.unmounted_player_art=="100001" and world.battle_view.actors[0].character_id=="100001","equipped ARM selects source CHAR_eqimagetbl axe sprite, never club; actual %s" % str(world.battle_view.actors[0].character_id))
	check(await Wait.until(self,func():return world.battle_view.actors[0].sprite.texture!=null),"real axe texture reaches first animation frame before inspection")
	world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();backend.queue_free()
	await process_frame
	remove_files("user://wood-equipment-viewer.cfg")
