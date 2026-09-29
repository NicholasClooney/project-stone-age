extends SceneTree
## 放生记录: every release path writes one entry with the reason and who beat
## it; the log lives in its own capped file next to the save and is never read
## when the save loads; it pages and filters, also over the WebSocket, and the
## pet window shows it.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const GameSession = preload("res://server/game_session.gd")
const ReleaseLog = preload("res://server/release_log.gd")
const KeepRule = preload("res://scripts/keep_rule.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const SAVE := "user://release-log-test-save.json"
const LOG := "user://release-log-test-save.release-log.jsonl"
const CAPPED := "user://release-log-test-capped.jsonl"
const PREFS := "user://release-log-test-viewer.cfg"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():return true
		await physics_frame
	return bool(condition.call())

func pet(id: int, attack: int, defence: int, speed: int, hp: int = 1300) -> Dictionary:
	return {"pet_id":"pet-%d" % id,"template_id":92,"species":"original_92","name":"扬奇洛斯","level":120,"attack":attack,"defence":defence,"speed":speed,"max_hp":hp,"hp":hp,"growth_weights":[29,38,18,22]}

## Two 626s; five 625s ranked 3, 4, 5, then 7 (a copy of 5) and 6; a 620.
func herd() -> Array:
	return [pet(1,294,179,153),pet(2,293,180,153),pet(3,294,178,153),pet(4,293,180,152),pet(5,292,180,153),pet(6,291,181,153),pet(7,292,180,153),pet(8,290,178,152)]

func cleanup() -> void:
	for path in [SAVE,SAVE+".bak",SAVE+".tmp",LOG,CAPPED,PREFS]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func keep_rule_reasons() -> void:
	var rule := {"tiers":2,"per_tier":3,"order":["attack","speed","max_hp"],"champions":0,"champion_stats":[]}
	var verdict := KeepRule.evaluate(herd(),rule)
	check(verdict.release==["pet-6","pet-7","pet-8"],"the rule keeps both 626s and the best three 625s")
	check(verdict.why["pet-6"].reason=="625档第5名，每档只留3只" and verdict.why["pet-6"].beaten_by==["pet-3","pet-4","pet-5"],"a pet past the tier quota names its place and the three quota holders")
	check(verdict.why["pet-7"].reason=="与 pet-5 属性完全相同，保留较早的" and verdict.why["pet-7"].beaten_by==["pet-5"],"a duplicate names the older identical pet that stays")
	check(verdict.why["pet-8"].reason=="三围合620，不在最高2档（626、625）" and verdict.why["pet-8"].beaten_by==["pet-1"],"a pet below the top tiers names the best kept pet at least as good in every stat")
	var with_champions := KeepRule.evaluate(herd(),Settings.default_stat_filter(92).keep_rule)
	check(with_champions.why.values().all(func(why):return str(why.reason).ends_with("单项未进前2")),"with single-stat champions on, each reason adds 单项未进前2")

func session_paths() -> void:
	var session := GameSession.new()
	session._profile.pets = [pet(20,280,170,140)]
	session._profile.pet_storage = herd()
	session._profile.active_pet = -1
	session._profile.ride_pet = -1
	session.release_pets(["pet-20"])
	var manual: Array = session.take_release_events()
	check(manual.size()==1 and manual[0].source=="手动" and manual[0].reason=="手动放生" and manual[0].where=="随身" and int(manual[0].sum)==590,"a manual release is logged as 手动放生 from 随身 with its stats")
	check(manual[0].full and manual[0].offsets==[2,2,2,2],"the entry keeps the innate grade (满档)")
	var released: Array = session.apply_keep_rule(92,{"tiers":2,"per_tier":3,"order":["attack","speed","max_hp"],"champions":0,"champion_stats":[]})
	var tidy: Array = session.take_release_events()
	check(released.size()==3 and tidy.size()==3 and tidy.all(func(item):return item.source=="自动整理" and item.where=="仓库"),"the find-pet tidy logs each release as 自动整理")
	var dup: Dictionary = tidy.filter(func(item):return item.pet_id=="pet-7")[0]
	check(dup.reason.begins_with("与 pet-5") and dup.beaten_by.size()==1 and dup.beaten_by[0].pet_id=="pet-5" and int(dup.beaten_by[0].sum)==625 and int(dup.beaten_by[0].attack)==292,"beaten_by carries the beater's id and stats")
	var rejects := [pet(30,280,170,140),pet(31,270,170,140),pet(32,260,170,140)]
	for item in rejects:item.auto_hunt = true
	session._profile.pet_storage = rejects
	session.prune_hunt_pets(92,{"sum":1},["pet-30","pet-31","pet-32"])
	var pruned: Array = session.take_release_events()
	check(pruned.size()==2 and pruned.all(func(item):return item.source=="未达标整理" and item.reason=="未达标，三围合未进前1" and item.beaten_by.map(func(b):return b.pet_id)==["pet-30"]),"reject pruning logs 未达标整理 with the quota it missed and the pet that kept the place")
	check(session.take_release_events().is_empty(),"taking the events empties them")

func capped_file() -> void:
	var log := ReleaseLog.new()
	log.path = CAPPED
	log.cap = 10
	log.slack = 5
	for i in range(16):log.append([ReleaseLog.entry(pet(100+i,290,178,150),"仓库","手动","手动放生")])
	var lines := FileAccess.get_file_as_string(CAPPED).split("\n",false)
	check(lines.size()==10 and JSON.parse_string(lines[-1]).pet_id=="pet-115" and JSON.parse_string(lines[0]).pet_id=="pet-106","over cap + slack the file keeps the newest cap entries")
	var other := ReleaseLog.entry(pet(200,200,100,100),"仓库","手动","手动放生")
	other.template_id = 194;other.name = "金虎"
	log.append([other])
	var first: Dictionary = log.page(0,4)
	check(first.total==11 and first.pages==3 and first.entries[0].pet_id=="pet-200" and first.entries[1].pet_id=="pet-115","pages come newest first")
	var dragons: Dictionary = log.page(1,4,92)
	check(dragons.total==10 and dragons.entries.size()==4 and dragons.entries[0].pet_id=="pet-111" and dragons.entries.all(func(item):return int(item.template_id)==92),"a species filter pages that species only")
	check(first.species.size()==2 and first.species.any(func(item):return int(item.template_id)==194 and item.count==1),"the page lists the species in the log with counts")
	check(log.page(99,4).page==2,"a page past the end shows the last one")
	var memory := ReleaseLog.new()
	memory.cap = 10
	memory.slack = 5
	for i in range(20):memory.append([ReleaseLog.entry(pet(300+i,290,178,150),"仓库","手动","手动放生")])
	check(memory.entries().size()==14 and memory.entries()[0].pet_id=="pet-306" and memory.page(0,20).entries[0].pet_id=="pet-319","without a save the log stays in memory, trimmed to the newest cap past cap + slack")

func backend_file() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	backend.save_path = SAVE
	backend.handle({"type":"grant_starter_pets"})
	backend.session._profile.pet_storage = herd()
	backend.handle({"type":"release_pets","ids":["pet-8"]})
	check(FileAccess.file_exists(LOG) and FileAccess.get_file_as_string(LOG).split("\n",false).size()==1,"a release writes one line to <save>.release-log.jsonl")
	check(not FileAccess.get_file_as_string(SAVE).contains("手动放生"),"the save itself holds no log")
	# 按保留规则选中 then 放生所选: the backend re-evaluates the rule for the reasons.
	var profile: Dictionary = backend.session.snapshot()
	var rule: Dictionary = Settings.stat_filter(backend.session.automation_settings(),92).keep_rule
	var protected: Dictionary = KeepRule.always_kept(profile)
	protected.merge(backend.automation.capture_helpers(),true)
	var verdict := KeepRule.evaluate(KeepRule.species_pets(profile,92),rule,protected)
	backend.handle({"type":"release_pets","ids":verdict.release,"source":"保留规则","template_id":92})
	var reply: Dictionary = backend.handle({"type":"release_log","page":0,"page_size":50,"template_id":92})
	var entries: Array = reply.log.entries
	check(reply.ok and entries.size()==1+verdict.release.size() and entries[-1].pet_id=="pet-8","release_log pages the file newest first")
	check(entries.slice(0,verdict.release.size()).all(func(item):return item.source=="保留规则" and item.reason!="手动放生" and not item.beaten_by.is_empty()),"rule releases from 同种比较 carry the rule's reasons and beaters")
	# A later load never reads the log.
	var fresh = Backend.new()
	root.add_child(fresh)
	fresh.save_path = SAVE
	check(fresh.load_profile(SAVE) and fresh.release_log._count==-1 and fresh.release_log.path.is_empty(),"loading the save does not open the log")
	check(fresh.handle({"type":"release_log"}).log.total==entries.size(),"the log is read when asked for")
	backend.queue_free();fresh.queue_free()
	await process_frame

func remote() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	backend.session._profile.pet_storage = herd()
	backend.handle({"type":"release_pets","ids":["pet-6"]})
	var port := 20000+randi()%20000
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online),"a remote device connects")
	var got := {}
	game.session.release_log(0,20,92,func(data:Dictionary):got.merge(data))
	check(await until(func():return not got.is_empty()) and got.entries.size()==1 and got.entries[0].pet_id=="pet-6","a remote device reads the log over the WebSocket")
	var menu = game.adventure_menu
	menu.open_release_log(92)
	check(await until(func():return menu.panel.find_child("ReleaseLogRow_0",true,false)!=null),"宠物记录 opens on 放生 in the pet window and lists the entry")
	var row = menu.panel.find_child("ReleaseLogRow_0",true,false)
	check(row.tooltip_text.contains("pet-6") and row.find_children("*","Label",true,false).any(func(label):return label.text=="手动放生"),"the row shows the pet and why it went")
	# A 按保留规则选中 release from this device is logged with the rule's reasons.
	check(menu.open_pet_comparison("pet-1"),"同种比较 opens on the remote device")
	menu.select_by_keep_rule(game.session.snapshot())
	var chosen: Array = menu.pet_release_selected.keys()
	menu.perform_release()
	check(await until(func():return backend.release_log.entries().size()==1+chosen.size()),"the remote release reaches the log")
	check(backend.release_log.entries().slice(1).all(func(item):return item.source=="保留规则" and chosen.has(item.pet_id)),"and is logged as 保留规则 with the rule's reasons")
	menu.open_release_log(-1)
	check(await until(func():return menu.panel.find_child("RecordsSpecies",true,false)!=null and menu.records_data.get("total",0)==1+chosen.size()),"the log view refreshes with the new entries")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame

func run() -> void:
	cleanup()
	keep_rule_reasons()
	session_paths()
	capped_file()
	await backend_file()
	await remote()
	cleanup()
	await create_timer(0.3).timeout
	print("RELEASE LOG: %d failures" % failures)
	quit(1 if failures else 0)
