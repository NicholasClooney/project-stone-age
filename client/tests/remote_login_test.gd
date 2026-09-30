extends SceneTree
## LAN phase 1 over a real localhost WebSocket: a server hosting several
## profiles (server/profile_hub.gd behind server/ws_server.gd), two devices
## logging into different characters and getting only their own updates, a
## reconnect that logs in again with the remembered token, and the game's
## 登录 screen: picking a character, a wrong and a right PIN, creating a new
## character (which then picks its look), and the admin-only tools hidden for
## an ordinary player.
const ProfileHub = preload("res://server/profile_hub.gd")
const WsServer = preload("res://server/ws_server.gd")
const WsLink = preload("res://network/ws_link.gd")
var failures := 0
var links: Array = []

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Waits up to seconds for condition, polling the test's own links.
func until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		for link in links:link.poll(1.0/60.0)
		if condition.call():return true
		await physics_frame
	return bool(condition.call())

static func remove_tree(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):return
	for sub in DirAccess.get_directories_at(folder):remove_tree(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

class Device extends RefCounted:
	var link
	var events: Array = []
	var login_info: Dictionary = {}
	var reply: Dictionary = {}
	func _init(url: String) -> void:
		link = WsLink.new(url)
		link.message.connect(func(event):events.append(event))
		link.login_needed.connect(func(info):login_info = info)
	func send_login(command: Dictionary) -> void:
		reply = {}
		link.login(command,func(answer):reply = answer)
	func count(type: String) -> int:
		return events.filter(func(event):return str(event.get("type",""))==type).size()

func run() -> void:
	var dir := "user://remote-login-test-%d" % OS.get_process_id()
	remove_tree(dir)
	var hub = ProfileHub.new(dir.path_join("accounts.json"))
	hub.share_dir = dir.path_join("share")
	root.add_child(hub)
	check(hub.start(),"a multi-profile server starts on an empty accounts file")
	var port := 20000+randi()%20000
	var server = WsServer.new(hub,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"it listens on localhost")
	var url := "ws://127.0.0.1:%d" % port

	# Two devices, two new characters.
	var alice := Device.new(url)
	var bob := Device.new(url)
	links = [alice.link,bob.link]
	alice.link.connect_now()
	bob.link.connect_now()
	check(await until(func():return not alice.login_info.is_empty() and not bob.login_info.is_empty()),"both devices are asked to log in")
	check(not alice.link.online and alice.login_info.profiles.is_empty() and alice.login_info.allow_create,"with no characters yet, they may create one")
	alice.send_login({"type":"create_profile","name":"Alice","pin":"1111"})
	check(await until(func():return alice.link.online),"Alice creates her character and is in")
	check(bool(alice.reply.get("created",false)) and bool(alice.link.account.admin) and not alice.link.login_token.is_empty(),"as the first character she is the admin, and her device keeps a token")
	bob.send_login({"type":"create_profile","name":"Alice","pin":"2222"})
	check(await until(func():return not bob.reply.is_empty()) and not bob.reply.ok and str(bob.reply.reason).contains("已被使用") and not bob.link.online,"a taken name is refused: %s" % str(bob.reply.get("reason","")))
	bob.send_login({"type":"create_profile","name":"Bob","pin":"2222"})
	check(await until(func():return bob.link.online) and not bool(bob.link.account.admin),"Bob creates his, an ordinary player")
	var snapshot_a: Array = alice.events.filter(func(event):return event.type=="snapshot")
	check(snapshot_a.size()==1 and bool(snapshot_a[0].options.admin) and str(snapshot_a[0].options.account)=="Alice","Alice's snapshot names her account")

	# Each device hears only its own character.
	for _i in range(10):await until(func():return false,0.02)
	alice.events.clear();bob.events.clear()
	alice.link.request({"type":"gm_grant_points","amount":5})
	check(await until(func():return alice.count("profile") > 0),"Alice's GM command updates her device")
	for _i in range(20):await until(func():return false,0.02)
	check(bob.events.is_empty(),"Bob's device hears nothing of it")
	var bob_reply := {}
	bob.link.request({"type":"gm_grant_points","amount":5},func(answer):bob_reply.merge(answer))
	check(await until(func():return not bob_reply.is_empty()) and not bob_reply.ok and str(bob_reply.reason).contains("管理员"),"Bob's GM command is refused: %s" % str(bob_reply.get("reason","")))
	check(int(hub.backends.bob.session.snapshot().player.stat_points)==0 and int(hub.backends.alice.session.snapshot().player.stat_points)==5,"only Alice's character changed")
	alice.events.clear()
	bob.link.request({"type":"heal"})
	check(await until(func():return bob.count("profile") > 0),"Bob's own command updates his device")
	for _i in range(20):await until(func():return false,0.02)
	check(alice.count("profile")==0,"and not Alice's")

	# A dropped connection logs in again by itself with the token.
	var token: String = alice.link.login_token
	for peer in server.clients():
		if hub.profile_of(peer.get_instance_id())=="alice":peer.close()
	check(await until(func():return not alice.link.online),"Alice's connection drops")
	alice.login_info = {}
	check(await until(func():return alice.link.online,15.0) and alice.login_info.is_empty() and alice.link.login_token==token,"and comes back logged in, without the login screen")

	# The game's login screen.
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = url
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await until(func():return is_instance_valid(game.login_screen) and game.login_screen.visible,10.0),"the game opens on the 登录 screen")
	var screen = game.login_screen
	check(screen.list.get_child_count()==2 and screen.find_child("Profile_Alice",true,false)!=null and screen.find_child("Profile_Bob",true,false).text.contains("在线"),"it lists both characters, Bob as online")
	check(screen.create_toggle.visible and not screen.create_box.visible,"creating a character is one click away")
	screen.find_child("Profile_Bob",true,false).pressed.emit()
	screen.pin.text = "9999"
	screen.login_button.pressed.emit()
	check(await until(func():return screen.error.text.contains("PIN 不对")),"a wrong PIN says so: %s" % screen.error.text)
	check(game.data.is_empty() and not game.link.online,"and the game waits")
	screen.pin.text = "2222"
	screen.login_button.pressed.emit()
	check(await until(func():return not game.data.is_empty() and game.link.online,15.0),"the right PIN enters the world")
	check(not screen.visible and not game.link_blocked(),"the login screen is gone")
	check(not game.is_admin() and game.account_name()=="Bob","the game knows it plays Bob, not an admin")
	game.dev_gm_menu.open_menu()
	check(not game.dev_gm_menu.visible,"GM 调试 does not open for a player")
	game.settings_menu.open_menu()
	check(game.settings_menu.find_child("SettingsDeveloper",true,false)==null and game.settings_menu.find_child("SettingsSwitchProfile",true,false)!=null,"设置 has 切换角色 and no 开发者 section")
	game.settings_menu.close_menu()
	game.queue_free()
	await process_frame

	# Creating a character from the game: it picks its look first.
	game_script.server_url_override = url
	var second = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	second.profile_persistence = false
	root.add_child(second)
	check(await until(func():return is_instance_valid(second.login_screen) and second.login_screen.visible,10.0),"a second game opens on the 登录 screen")
	var create = second.login_screen
	create.create_toggle.pressed.emit()
	create.new_name.text = "小红"
	create.new_pin.text = "3333"
	create.new_pin_again.text = "3334"
	create.create_button.pressed.emit()
	check(create.error.text.contains("不一样") and second.data.is_empty(),"mistyped PINs are caught before sending")
	create.new_pin_again.text = "3333"
	create.create_button.pressed.emit()
	check(await until(func():return not second.data.is_empty(),15.0),"the new character enters the world")
	check(await until(func():return second.character_selection.visible,5.0) and second.character_selection.title_label.text.begins_with("新角色"),"and chooses its look first")
	check(hub.accounts.find("小红").size() > 0 and hub.backends.size()==3,"the server has three characters, each with its own backend")
	second.character_selection.close_menu()
	second.queue_free()
	await process_frame

	for link in links:
		link.close()
		for name in ["message","login_needed"]:
			for connection in link.get_signal_connection_list(name):link.disconnect(name,connection.callable)
	links.clear()
	server.stop()
	hub.shut_down()
	server.queue_free()
	hub.queue_free()
	await process_frame
	remove_tree(dir)
	print("REMOTE LOGIN: %d failures" % failures)
	quit(1 if failures else 0)
