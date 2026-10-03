extends SceneTree
## LAN phase 1 (docs/development/lan-profiles.md): one server hosts many
## profiles. Accounts (name + salted PIN hash, device tokens, lock-out after
## wrong PINs), the profile hub routing each connection's commands and events
## to its own profile's backend only, admin-only GM and developer commands,
## per-profile saves, locks, backups and restart-resume files, and the shared
## automation frame budget and fast hunt share.
##
## The functional core runs for real (accounts, hub, backends, saves, the
## automation's resume path). Only the shell is faked: the clock, the folders
## (a private user:// folder), and connections (plain ids instead of sockets;
## remote_login_test covers the WebSocket and the client's login screen).
const Accounts = preload("res://server/accounts.gd")
const ProfileHub = preload("res://server/profile_hub.gd")
const SaveBackups = preload("res://server/save_backups.gd")
const SaveLock = preload("res://server/save_lock.gd")
const FastHuntShare = preload("res://server/fast_hunt_share.gd")
const MAP := 300
const CELL := [509,93]
var failures := 0
var now := 1000.0
var dir := ""

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clock() -> float:
	return now

static func remove_tree(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):return
	for sub in DirAccess.get_directories_at(folder):remove_tree(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

func run() -> void:
	dir = "user://profile-hub-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	accounts()
	backups()
	await routing()
	remove_tree(dir)
	print("PROFILE HUB: %d failures" % failures)
	quit(1 if failures else 0)

## Names, PINs, hashes, tokens and the lock-out.
func accounts() -> void:
	var path := dir.path_join("accounts-unit.json")
	var book = Accounts.new(path,clock)
	check(book.load_file() and book.profiles().is_empty(),"a missing accounts file is an empty list")
	var first: Dictionary = book.create("Nicholas","1234")
	check(first.ok and first.entry.admin and first.entry.id=="nicholas","the first character is the admin, its id the plain name")
	var second: Dictionary = book.create("小明","5678")
	check(second.ok and not second.entry.admin and second.entry.id=="p1","later characters are not; a Chinese name gets a file-safe id (%s)" % str(second.get("entry",{}).get("id","")))
	check(book.save_path(second.entry)==dir.path_join("p1.json"),"its save sits next to the accounts file")
	check(not book.create("nicholas","1111").ok,"names are unique regardless of case")
	check(not book.create("x","12").ok and not book.create("x","12ab").ok and not book.create("x","123456789").ok,"a PIN is 4 to 8 digits")
	check(not book.create("  ","1234").ok and not book.create("一二三四五六七八九十一二三四五六七","1234").ok,"a name is 1 to 16 characters")
	var text := FileAccess.get_file_as_string(path)
	check(not text.contains("\"1234\"") and not text.contains("\"5678\"") and text.contains(Accounts.hash_pin(str(first.entry.salt),"1234")),"the file keeps salted hashes, never a PIN")
	check(first.entry.salt!=second.entry.salt,"every profile has its own salt")
	var again = Accounts.new(path,clock)
	check(again.load_file() and again.profiles().size()==2 and again.is_admin("nicholas") and not again.is_admin("p1"),"the file reads back")
	check(book.verify_pin("NICHOLAS","1234").ok,"the right PIN logs in (the name ignores case)")
	var wrong: Dictionary = book.verify_pin("nicholas","0000")
	check(not wrong.ok and str(wrong.reason).contains("还可以再试 4 次"),"a wrong PIN is refused: %s" % wrong.reason)
	check(not book.verify_pin("nobody","1234").ok,"an unknown name is refused")
	for i in range(3):book.verify_pin("nicholas","0000")
	var locked: Dictionary = book.verify_pin("nicholas","0000")
	check(not locked.ok and int(locked.get("locked",0))==Accounts.LOCK_SECONDS,"five wrong PINs in a row lock the profile: %s" % locked.reason)
	check(not book.verify_pin("nicholas","1234").ok and book.verify_pin("小明","5678").ok,"then even the right PIN waits, while other profiles are unaffected")
	now += Accounts.LOCK_SECONDS-1
	check(book.locked_for("nicholas")==1,"the lock lasts %d s" % Accounts.LOCK_SECONDS)
	now += 2
	check(book.verify_pin("nicholas","1234").ok,"afterwards the right PIN works again")
	check(book.verify_pin("nicholas","0000").reason.contains("4 次"),"and the count starts over")
	var token: String = book.issue_token("nicholas")
	check(token.length()==32 and book.verify_token("nicholas",token).ok,"a device token logs in without the PIN")
	check(not FileAccess.get_file_as_string(path).contains(token),"the file keeps only the token's hash")
	check(not book.verify_token("小明",token).ok and not book.verify_token("nicholas","").ok,"a token belongs to its own profile")
	for i in range(Accounts.MAX_TOKENS):book.issue_token("nicholas")
	check(not book.verify_token("nicholas",token).ok and book.by_id("nicholas").tokens.size()==Accounts.MAX_TOKENS,"only the newest %d devices are remembered" % Accounts.MAX_TOKENS)
	var kept: String = book.issue_token("p1")
	book.revoke_token("p1",kept)
	check(not book.verify_token("小明",kept).ok,"退出登录 forgets that device")
	kept = book.issue_token("p1")
	check(book.set_pin("小明","9999").is_empty() and book.verify_pin("小明","9999").ok and not book.verify_token("小明",kept).ok,"a new PIN logs every device out")
	book.data.allow_create = false
	book.save_file()
	check(not book.create("客人","1234").ok and book.create("客人","1234",false).ok,"with allow_create off only the tool adds characters")
	# The tool edits the file while a server runs: the server sees it at the next login.
	var tool = Accounts.new(path,clock)
	tool.load_file()
	tool.find("客人").admin = true
	tool.save_file()
	var mtime := FileAccess.get_modified_time(path)
	while FileAccess.get_modified_time(path)==mtime:
		OS.delay_msec(50)
		tool.save_file()
	book.reload_if_changed()
	check(book.find("客人").admin,"a running server picks up the edited file")
	FileAccess.open(dir.path_join("broken.json"),FileAccess.WRITE).store_string("{\"profiles\":[{\"id\":\"a\",\"name\":\"a\",\"salt\":\"s\",\"pin\":\"p\"},{\"id\":\"b\",\"name\":\"A\",\"salt\":\"s\",\"pin\":\"p\"}]}")
	var broken = Accounts.new(dir.path_join("broken.json"))
	check(not broken.load_file() and broken.last_error.contains("重复"),"a file with clashing names is refused, not overwritten: %s" % broken.last_error)

## Dated copies, the newest few kept.
func backups() -> void:
	var save := dir.path_join("backup-me.json")
	check(SaveBackups.backup(save).is_empty(),"no save, no copy")
	FileAccess.open(save,FileAccess.WRITE).store_string("{}")
	for i in range(7):SaveBackups.backup(save,5,"2026093%d-000000" % i)
	var copies := SaveBackups.copies_of(save)
	check(copies.size()==5 and copies[0]=="backup-me@20260932-000000.json","the newest 5 copies are kept (%s)" % str(copies))
	FileAccess.open(dir.path_join("backups").path_join("backup-me-too@20260101-000000.json"),FileAccess.WRITE).store_string("{}")
	check(SaveBackups.copies_of(save).size()==5,"another save's copies are not counted")

class Wire extends RefCounted:
	var messages: Dictionary = {}
	func take(connection: int, message: Dictionary) -> void:
		if not messages.has(connection):messages[connection] = []
		messages[connection].append(message)
	func of(connection: int, type: String = "") -> Array:
		return messages.get(connection,[]).filter(func(message):return type.is_empty() or str(message.type)==type)
	func clear() -> void:
		messages.clear()

func new_hub(path: String):
	var hub = ProfileHub.new(path,clock)
	hub.tick = false
	hub.share_dir = dir.path_join("share")
	root.add_child(hub)
	return hub

## Two players, each with their own backend, commands and events.
func routing() -> void:
	var path := dir.path_join("hub").path_join("accounts.json")
	var hub = new_hub(path)
	check(hub.start() and hub.backends.is_empty(),"a hub starts with no profile open")
	var wire := Wire.new()
	hub.outgoing.connect(wire.take)
	var hello: Dictionary = hub.handle(1,{"type":"hello","protocol":1,"seq":1})
	check(hello.ok and hello.login_required and hello.profiles.is_empty() and hello.allow_create and not hello.has("snapshot"),"hello asks a new device to log in or create a character")
	var refused: Dictionary = hub.handle(1,{"type":"heal","seq":2})
	check(not refused.ok and refused.get("login_required",false),"nothing else is accepted before a login")
	var alice: Dictionary = hub.handle(1,{"type":"create_profile","name":"Alice","pin":"1111","seq":3})
	check(alice.ok and alice.created and alice.account.admin and alice.has("snapshot") and not str(alice.token).is_empty(),"the first character created is the admin and is logged in at once")
	check(bool(alice.snapshot.options.admin) and str(alice.snapshot.options.account)=="Alice","its snapshot says so")
	var bob: Dictionary = hub.handle(2,{"type":"create_profile","name":"Bob","pin":"2222","seq":1})
	check(bob.ok and not bob.account.admin and not bool(bob.snapshot.options.admin),"the second is an ordinary player")
	var a = hub.backends.alice
	var b = hub.backends.bob
	check(a!=b and a.save_path!=b.save_path and FileAccess.file_exists(a.save_path) and FileAccess.file_exists(b.save_path),"each has its own backend and save (%s, %s)" % [a.save_path,b.save_path])
	check(SaveLock.holder_pid(a.save_path)==OS.get_process_id() and SaveLock.holder_pid(b.save_path)==OS.get_process_id(),"and holds its save's lock")
	check(a.automation.fast_share!=null and b.automation.fast_share!=null and a.automation.fast_share.id!=b.automation.fast_share.id,"and is its own participant in the fast hunt share")
	check(a.automation.client_attached and b.automation.client_attached,"a logged-in device paces its own profile's automation")

	# Commands and events stay with their profile.
	wire.clear()
	var points: int = int(a.session.snapshot().player.stat_points)
	check(hub.handle(1,{"type":"gm_grant_points","amount":3,"seq":4}).ok and int(a.session.snapshot().player.stat_points)==points+3,"the admin's GM command changes the admin's character")
	check(int(b.session.snapshot().player.stat_points)==0,"and not the other one")
	check(wire.of(1,"profile").size()==1 and wire.of(2).is_empty(),"only the admin's devices get the update")
	wire.clear()
	b.session._profile.player.hp = 1
	check(hub.handle(2,{"type":"heal","seq":2}).ok,"a player heals")
	check(wire.of(2,"profile").size()==1 and wire.of(1).is_empty(),"and only that player's devices hear of it")

	# Admin-only tools.
	for command in [{"type":"gm_grant_points","amount":3},{"type":"gm_heal","index":-2},{"type":"gm_grant_pet","template":92},{"type":"begin_battle"},{"type":"start_battle_config"},{"type":"set_fast_hunt_threads","threads":1},{"type":"battle_escape_dev"}]:
		var reply: Dictionary = hub.handle(2,command)
		check(not reply.ok and str(reply.reason).contains("管理员"),"%s is refused for a player" % command.type)
	check(int(b.session.snapshot().player.stat_points)==0,"nothing changed")
	check(hub.handle(2,{"type":"set_options","experience_multiplier":10}).ok,"the training helper's 经验倍率 stays a player setting")

	# A second device of Alice's, remembered by its token, sees Alice's updates.
	wire.clear()
	var remembered: Dictionary = hub.handle(3,{"type":"hello","protocol":1,"login":{"name":"alice","token":alice.token}})
	check(remembered.ok and remembered.has("snapshot") and hub.profile_of(3)=="alice","a remembered device logs in with its token")
	var stale: Dictionary = hub.handle(4,{"type":"hello","protocol":1,"login":{"name":"alice","token":"nope"}})
	check(stale.login_required and str(stale.get("reason","")).contains("失效"),"a wrong token falls back to the login screen")
	hub.handle(1,{"type":"gm_heal","index":-2})
	check(wire.of(1,"profile").size()==1 and wire.of(3,"profile").size()==1 and wire.of(2).is_empty() and wire.of(4).is_empty(),"both of Alice's devices get her update, Bob's and the stranger's none")
	var listing: Array = hub.handle(4,{"type":"hello","protocol":1}).profiles
	check(listing.size()==2 and listing[0].name=="Alice" and listing[0].online and listing[0].admin and not listing[1].admin,"the picker lists both, online, with the admin marked")

	# Logging in with a PIN; wrong PINs lock the profile out.
	for i in range(4):hub.handle(4,{"type":"login","name":"bob","pin":"0000"})
	var lock: Dictionary = hub.handle(4,{"type":"login","name":"bob","pin":"0000"})
	check(not lock.ok and lock.has("locked") and hub.profile_of(4).is_empty(),"five wrong PINs lock Bob out: %s" % lock.reason)
	check(not hub.handle(4,{"type":"login","name":"bob","pin":"2222"}).ok,"even the right PIN waits")
	now += Accounts.LOCK_SECONDS+1
	check(hub.handle(4,{"type":"login","name":"bob","pin":"2222"}).ok and hub.profile_of(4)=="bob","after the lock-out Bob logs in on a second device")
	check(hub.handle(4,{"type":"logout"}).ok and hub.profile_of(4).is_empty() and not hub.handle(4,{"type":"heal"}).ok,"退出登录 returns that device to the picker")

	# Disconnects.
	hub.disconnect_connection(1)
	check(a.automation.client_attached,"Alice's automation still paces for her other device")
	hub.disconnect_connection(3)
	check(not a.automation.client_attached and hub.backends.has("alice"),"with no device left it runs detached, and her backend stays open")

	# The automation frame budget is split among the busy profiles.
	check(hub.share_budget()==0 and a.automation.frame_budget(12000)==12000,"idle profiles keep the whole budget")
	a.automation.running = true
	a.automation.settings = {"compact":true,"speed":8.0}
	check(hub.share_budget()==1 and a.automation.frame_budget(12000)==12000,"one busy profile gets all 12 ms")
	b.automation.hunt_running = true
	check(hub.share_budget()==2 and a.automation.frame_budget(12000)==6000 and b.automation.frame_budget(12000)==6000,"two busy profiles get 6 ms each")
	a.automation.budget_share = 50
	check(a.automation.frame_budget(12000)==1000,"never less than 1 ms")
	a.automation.running = false
	b.automation.hunt_running = false
	hub.share_budget()

	# Both play (a hunt each), then the server stops gracefully and restarts.
	for pair in [[1,"alice","1111"],[2,"bob","2222"]]:
		hub.handle(pair[0],{"type":"login","name":pair[1],"pin":pair[2]})
		hub.handle(pair[0],{"type":"report_position","map_id":MAP,"cell":CELL})
		var started: Dictionary = hub.handle(pair[0],{"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL,"filter":{"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"limit":0,"rate":1,"fast":false}})
		check(started.ok,"%s starts a hunt %s" % [pair[1],str(started)])
	a.automation.tick(0.5)
	b.automation.tick(0.5)
	check(a.automation.hunt_running and b.automation.hunt_running,"both hunt at once")
	var saves := [a.save_path,b.save_path]
	hub.shut_down()
	for save in saves:
		check(FileAccess.file_exists(ProfileHub.resume_file(save)),"a graceful stop writes %s" % ProfileHub.resume_file(save).get_file())
		check(SaveLock.holder_pid(save)==0,"and releases %s's lock" % save.get_file())
	hub.queue_free()
	await process_frame

	var restarted = new_hub(path)
	check(restarted.start() and restarted.backends.size()==2,"after a restart both profiles open without a login")
	for id in ["alice","bob"]:
		var backend = restarted.backends.get(id)
		check(backend!=null and not backend.automation.pending_resume.is_empty() and not FileAccess.file_exists(ProfileHub.resume_file(backend.save_path)),"%s's run is waiting to resume" % id)
		if backend==null:continue
		backend.automation.tick(0.1)
		check(backend.automation.hunt_running and not backend.automation.client_attached,"and %s's hunt goes on with nobody connected" % id)
	check(SaveBackups.copies_of(saves[0]).size()==1 and SaveBackups.copies_of(saves[1]).size()==1,"opening an existing save takes a dated backup (%s)" % str(SaveBackups.copies_of(saves[0])))
	restarted.shut_down()
	restarted.queue_free()
	await process_frame
