extends SceneTree
## Edits a multi-profile server's accounts file (server/accounts.gd); run it
## through scripts/accounts.sh, which asks for PINs without echoing them and
## passes them in STONE_AGE_PIN. A running server picks the changes up at the
## next login. Commands (after --):
##   [--accounts=user://lan/accounts.json] list
##   add <name> [--save=user://single-player.json] [--admin | --no-admin]
##   pin <name>              new PIN; every remembered device logs in again
##   admin <name> on|off
##   create on|off           whether clients may create characters
##   remove <name>           removes the account, never the save
const Accounts = preload("res://server/accounts.gd")
const DEFAULT_PATH := "user://lan/accounts.json"

func _initialize() -> void:
	var path := DEFAULT_PATH
	var words: Array = []
	var flags := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--accounts="):path = argument.trim_prefix("--accounts=")
		elif argument.begins_with("--save="):flags.save = argument.trim_prefix("--save=")
		elif argument=="--admin":flags.admin = true
		elif argument=="--no-admin":flags.admin = false
		else:words.append(argument)
	var accounts = Accounts.new(path)
	if not accounts.load_file():
		printerr(accounts.last_error)
		quit(1)
		return
	var error := run(accounts,words,flags)
	if not error.is_empty():printerr(error)
	quit(1 if not error.is_empty() else 0)

func run(accounts, words: Array, flags: Dictionary) -> String:
	var command := str(words[0]) if not words.is_empty() else "list"
	var name := str(words[1]) if words.size() > 1 else ""
	var pin := OS.get_environment("STONE_AGE_PIN")
	match command:
		"list":
			print("账号文件：%s" % ProjectSettings.globalize_path(accounts.path))
			print("客户端可新建角色：%s" % ("是" if accounts.allow_create() else "否"))
			if accounts.profiles().is_empty():print("（还没有角色；第一个创建的角色是管理员）")
			for entry in accounts.profiles():
				print("  %s%s  存档 %s  已记住设备 %d" % [entry.name,"（管理员）" if entry.admin else "",ProjectSettings.globalize_path(accounts.save_path(entry)),entry.get("tokens",[]).size()])
			return ""
		"add":
			if name.is_empty():return "用法：add <名字> [--save=user://...] [--admin]"
			var created: Dictionary = accounts.create(name,pin,false,flags.get("admin"),str(flags.get("save","")))
			if not created.ok:return str(created.reason)
			print("已添加「%s」%s，存档 %s。" % [created.entry.name,"（管理员）" if created.entry.admin else "",ProjectSettings.globalize_path(accounts.save_path(created.entry))])
			return ""
		"pin":
			var problem: String = accounts.set_pin(name,pin)
			if problem.is_empty():print("「%s」的 PIN 已更换；已记住的设备需要重新登录。" % name)
			return problem
		"admin":
			var entry: Dictionary = accounts.find(name)
			if entry.is_empty():return "没有叫「%s」的角色。" % name
			entry.admin = words.size() > 2 and str(words[2])=="on"
			print("「%s」%s管理员。" % [entry.name,"现在是" if entry.admin else "不再是"])
			return "" if accounts.save_file() else "无法写入账号文件。"
		"create":
			accounts.data.allow_create = str(name)=="on"
			print("客户端%s新建角色。" % ("可以" if accounts.allow_create() else "不能"))
			return "" if accounts.save_file() else "无法写入账号文件。"
		"remove":
			var entry: Dictionary = accounts.find(name)
			if entry.is_empty():return "没有叫「%s」的角色。" % name
			accounts.profiles().erase(entry)
			print("已删除账号「%s」；存档 %s 保留。" % [entry.name,ProjectSettings.globalize_path(accounts.save_path(entry))])
			return "" if accounts.save_file() else "无法写入账号文件。"
	return "未知命令 %s（list、add、pin、admin、create、remove）" % command
