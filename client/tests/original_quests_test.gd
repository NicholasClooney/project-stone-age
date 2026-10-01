extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Quests=preload("res://server/original_quests.gd")
const Hub=preload("res://server/profile_hub.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func near(backend, id: String) -> void:
	var npc: Dictionary=backend.original_quests.npc_by_id(id)
	backend.automation.position_map=int(npc.map_id)
	backend.automation.position_cell=Vector2i(int(npc.cell[0])+1,int(npc.cell[1]))
func talk(backend,id: String) -> Dictionary:
	near(backend,id)
	return backend.handle({"type":"quest_talk","npc_id":id})
func choose(backend,reply: Dictionary,choice: String) -> Dictionary:
	return backend.handle({"type":"quest_choose","token":reply.get("dialogue",{}).get("token",""),"choice":choice})
func fresh():
	var b=Backend.new()
	b.quest_catalog.enabled_events=[2]
	return b
func run() -> void:
	migration()
	for bit in range(4):direction(bit)
	rejections()
	lan()
	print("ORIGINAL QUESTS: %d failures" % failures)
	quit(1 if failures else 0)
func migration() -> void:
	var path: String="user://original-quests-migration.json"
	for version in range(1,5):
		var session=Session.new()
		session.grant_starter_pets()
		session.select_pet(0)
		session.mount_pet(1)
		session.store_pet(2)
		session.gm_grant_points(7)
		session.allocate_stat("strength",3)
		session._profile.default_companions_claimed=true
		session._profile.gm_modified=true
		session._profile.quest={"accepted":true,"wins":7,"boss_defeated":true,"claimed":true}
		session._profile.completed_battles=["battle-1","battle-2"]
		session._profile.next_battle=3
		session._profile.music={"favorites":["sabgm_01"],"playlists":[{"name":"旅途","tracks":["sabgm_01","sabgm_02"]}]}
		session._profile.automation_settings={"training":{"xp":10,"compact":true,"hp":50},"hunt":{"resume":true,"rate":4}}
		session._profile.automation_settings=preload("res://scripts/automation_settings.gd").sanitize(session._profile.automation_settings)
		session._profile.inventory.club=1
		session.equip_item("club")
		session.set_character("100010")
		var old: Dictionary=session.snapshot()
		old.version=version
		for key in Session.ORIGINAL_DEFAULT:old.erase(key)
		old.location={"map_id":2000,"x":55,"y":92}
		old.inventory.potion=37
		old.travel_pass=true
		var file=FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(old));file.close()
		check(session.load_game(path),"load legacy v%d" % version)
		var migrated: Dictionary=session.snapshot()
		check(migrated.version==5 and migrated.original_items.is_empty() and migrated.origin.village_id==1000 and migrated.location==old.location and migrated.inventory.potion==37 and migrated.travel_pass,"v%d retains stacks/location/pass, origin not inferred from map" % version)
		check(migrated.pets==old.pets and migrated.pet_storage==old.pet_storage and migrated.player==old.player and migrated.character_id==old.character_id and migrated.equipped==old.equipped and migrated.quest==old.quest,"v%d preserves pets/stats/charm/luck/flags/equipment/character" % version)
		for key in ["active_pet","ride_pet","equipment","allocated_stats","gm_modified","gm_bonus_points","default_companions_claimed","music","automation_settings","completed_battles","next_battle"]:
			if key=="allocated_stats":check(migrated.player[key]==old.player[key],"allocated stats preserved")
			else:check(migrated.get(key)==old.get(key),"v%d preserves %s" % [version,key])
		check(session.save_game(path) and session.load_game(path),"v%d migration is reloadable" % version)
		check(session.snapshot()==migrated,"v5 reload does not repeat or change migration")
	var session=Session.new()
	check(session.save_game(path),"valid v5 saved")
	var good: Dictionary=session.snapshot()
	for key in Session.ORIGINAL_DEFAULT:
		var bad: Dictionary=good.duplicate(true);bad.erase(key)
		check(not session._valid_profile(bad),"v5 missing %s rejected" % key)
	for bad_words in [[0,0],[-1,0,0,0,0,0],[4294967296,0,0,0,0,0],[0.5,0,0,0,0,0]]:
		var bad: Dictionary=good.duplicate(true);bad.original_events.now=bad_words
		check(not session._valid_profile(bad),"invalid flag words rejected")
	var bad_items: Dictionary=good.duplicate(true)
	bad_items.original_items.resize(16);bad_items.original_items.fill(2414)
	check(not session._valid_profile(bad_items),"v5 cannot hide more than 15 original instances")
	Quests.set_flag(good,"now",2,false);Quests.set_flag(good,"now",2,false)
	check(not Quests.flag(good,"now",2),"clear NOW is idempotent")
	check(session.save_game(path),"valid backup created")
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string("corrupt");file.close()
	check(Session.new().load_game(path),"corruption falls back to validated backup")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
func direction(bit: int) -> void:
	var b=fresh()
	b.session._profile.original_savepoint_bits=1<<bit
	var start: String="sainasu/event/event02_2" if bit in [0,3] else "sainasu/event/event02_1"
	var finish: String="sainasu/event/event02_1" if bit in [0,3] else "sainasu/event/event02_2"
	var input:=2415 if bit in [0,3] else 2414
	var output:=2414 if bit in [0,3] else 2415
	var opened:=talk(b,start)
	check(opened.ok and choose(b,opened,"no").ok and b.session.snapshot().original_items.is_empty(),"SP%d REQUEST no preserves" % bit)
	var requested:=choose(b,talk(b,start),"yes")
	check(requested.ok and b.session.snapshot().original_items==[input] and Quests.flag(b.session.snapshot(),"now",2),"SP%d REQUEST receives original item" % bit)
	var accepted:=talk(b,finish)
	check(choose(b,accepted,"no").ok and b.session.snapshot().original_items==[input],"ACCEPT no preserves")
	var thanks:=choose(b,talk(b,finish),"yes")
	check(thanks.ok and b.session.snapshot().original_items==[input],"ACCEPT yes only shows thanks")
	var token: String=thanks.dialogue.token
	check(choose(b,thanks,"ok").ok and b.session.snapshot().original_items==[output] and Quests.flag(b.session.snapshot(),"ended",2) and not Quests.flag(b.session.snapshot(),"now",2),"SP%d second ACK swaps and ends" % bit)
	check(not b.handle({"type":"quest_choose","token":token,"choice":"ok"}).ok,"reward replay rejected")
	check(b.quest_catalog.journal(b.session.snapshot())[0].state=="已完成","journal from ended flag")
	var path: String="user://original-quest-sp%d.json" % bit
	var loaded=Session.new()
	check(b.session.save_game(path) and loaded.load_game(path) and loaded.snapshot().original_items==[output] and loaded.snapshot().original_events==b.session.snapshot().original_events and loaded.snapshot().original_savepoint_bits==(1<<bit),"original reward and six-word flags survive save/reload")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	check(b.handle({"type":"quest_discard","item_id":output}).ok,"server discards final reward")
	var clean:=talk(b,finish)
	check(choose(b,clean,"no").ok and Quests.flag(b.session.snapshot(),"ended",2),"CLEAN no preserves")
	check(choose(b,talk(b,finish),"yes").ok and not Quests.flag(b.session.snapshot(),"ended",2),"CLEAN clears lost reward quest")
	b.free()
func rejections() -> void:
	var b=fresh();var id: String="sainasu/event/event02_2"
	check(not b.handle({"type":"quest_talk","npc_id":id,"cell":[57,124]}).ok,"client position cannot open distant NPC")
	var opened:=talk(b,id)
	check(b.handle({"type":"quest_close","token":opened.dialogue.token}).ok and not choose(b,opened,"yes").ok and b.session.snapshot().original_items.is_empty(),"close cancels without mutations")
	opened=talk(b,id)
	Quests.set_flag(b.session._profile,"now",2,true)
	check(not choose(b,opened,"yes").ok and b.session.snapshot().original_items.is_empty(),"REQUEST phase rechecks NOW, prevents duplicate receipt")
	Quests.set_flag(b.session._profile,"now",2,false)
	opened=talk(b,id);b.automation.position_cell+=Vector2i(9,0)
	check(not choose(b,opened,"yes").ok,"movement invalidates confirm")
	opened=talk(b,id);b.battle_open=true
	check(not choose(b,opened,"yes").ok,"battle invalidates confirm");b.battle_open=false
	opened=talk(b,id);b.automation.running=true
	check(not choose(b,opened,"yes").ok,"automation invalidates confirm");b.automation.running=false
	b.session._profile.original_items=[]
	for i in range(14):b.session._profile.original_items.append(2414)
	check(Session.bag_slots(b.session.snapshot())==15,"legacy stack occupies one visible slot")
	var before: Dictionary=b.session.snapshot()
	check(not choose(b,talk(b,id),"yes").ok and b.session.snapshot()==before,"full bag transaction leaves flags untouched")
	b.session._profile.original_items=[]
	choose(b,talk(b,id),"yes")
	for i in range(13):b.session._profile.original_items.append(2414)
	var thanks:=choose(b,talk(b,"sainasu/event/event02_1"),"yes")
	var flower_index: int=b.session._profile.original_items.find(2415)
	b.session._profile.original_items.erase(2415)
	var failed_before: Dictionary=b.session.snapshot()
	check(not choose(b,thanks,"ok").ok and b.session.snapshot()==failed_before,"lost input rejects second ACCEPT acknowledgement without rewards")
	b.session._profile.original_items.insert(flower_index,2415)
	thanks=choose(b,talk(b,"sainasu/event/event02_1"),"yes")
	check(choose(b,thanks,"ok").ok and Session.bag_slots(b.session.snapshot())==15,"full bag ACCEPT credits deleted item slot atomically")
	b.session._profile.original_items=[]
	Quests.set_flag(b.session._profile,"ended",2,false)
	b.save_path="user://missing-quest-dir/save.json"
	before=b.session.snapshot()
	check(not choose(b,talk(b,id),"yes").ok and b.session.snapshot()==before,"failed disk write rolls back reward and flags")
	b.save_path=""
	choose(b,talk(b,id),"yes")
	b.session._profile.original_items.append(2415)
	var charm: int=b.session.snapshot().player.charm
	check(choose(b,talk(b,id),"no").ok and b.session.snapshot().original_items.count(2415)==2,"cancel no keeps duplicate items")
	check(choose(b,talk(b,id),"yes").ok and not 2415 in b.session.snapshot().original_items and not Quests.flag(b.session.snapshot(),"now",2) and b.session.snapshot().player.charm==charm-1,"cancel deletes all REQUEST copies and subtracts charm")
	b.session._profile.original_savepoint_bits=15
	check(b.original_quests.branch_for(b.original_quests.npc_by_id("sainasu/event/event02_1"),b.session.snapshot()).type=="REQUEST" and b.original_quests.branch_for(b.original_quests.npc_by_id("sainasu/event/event02_2"),b.session.snapshot()).type=="REQUEST","cumulative SP bits permit both original REQUEST directions")
	b.free()
func lan() -> void:
	var dir: String="user://original-quests-hub-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var hub=Hub.new(dir.path_join("accounts.json"))
	hub.tick=false;hub.backups=false;hub.share_dir=""
	check(hub.start(),"real ProfileHub starts")
	check(hub.handle(1,{"type":"create_profile","name":"Alice","pin":"1111"}).ok and hub.handle(2,{"type":"create_profile","name":"Bob","pin":"2222"}).ok and hub.handle(3,{"type":"login","name":"Alice","pin":"1111"}).ok,"two profiles and two Alice devices login")
	var a=hub.backend_of(1);var b=hub.backend_of(2)
	a.quest_catalog.enabled_events=[2];b.quest_catalog.enabled_events=[2]
	near(a,"sainasu/event/event02_2");near(b,"sainasu/event/event02_2")
	var first: Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":"sainasu/event/event02_2"})
	var other: Dictionary=hub.handle(2,{"type":"quest_talk","npc_id":"sainasu/event/event02_2"})
	var second: Dictionary=hub.handle(3,{"type":"quest_talk","npc_id":"sainasu/event/event02_2"})
	check(not hub.handle(1,{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"}).ok,"second device supersedes first token")
	check(hub.handle(3,{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"}).ok and b.session.snapshot().original_items.is_empty(),"Alice mutation isolated from Bob")
	check(not hub.handle(2,{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"}).ok,"foreign token rejected")
	# A failed foreign token must not consume Bob's pending dialogue.
	check(hub.handle(2,{"type":"quest_choose","token":other.dialogue.token,"choice":"yes"}).ok,"Bob pending still valid")
	hub.shut_down();hub.free()
	for file in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
