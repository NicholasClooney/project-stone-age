extends RefCounted
## LAN accounts for one server hosting many profiles (server/profile_hub.gd,
## docs/development/lan-profiles.md): a name, a PIN, a save and an admin flag
## per character, in one JSON file next to the saves:
##   {"version":1, "allow_create":true, "profiles":[{"id", "name", "save",
##    "admin", "salt", "pin", "tokens":[...], "created"}]}
## The PIN is never stored: `pin` is SHA-256 of `salt:pin` with a random salt
## per profile. A device that logged in keeps a random token instead of the
## PIN; the file keeps only the tokens' hashes (MAX_TOKENS per profile, the
## oldest dropped first). Wrong PINs are counted per profile: after
## MAX_FAILURES in a row the profile is locked for LOCK_SECONDS. LAN only: no
## email, no recovery (an admin resets a PIN with scripts/accounts.sh).
const VERSION := 1
const MAX_FAILURES := 5
const LOCK_SECONDS := 300
const MAX_TOKENS := 8
const NAME_LENGTH := 16
const MAX_PROFILES := 32

var path := ""
## Unix seconds; tests pass a fake.
var clock: Callable = Time.get_unix_time_from_system
var data: Dictionary = {"version":VERSION,"allow_create":true,"profiles":[]}
## Why the last load failed, "" when it did not.
var last_error := ""
## id -> {count, until}: wrong PINs in a row and the lock-out's end.
var _failures: Dictionary = {}
var _loaded_mtime := -1

func _init(file: String = "", fake_clock: Callable = Callable()) -> void:
	path = file
	if fake_clock.is_valid():clock = fake_clock

## Whether an accounts file exists at `file`.
static func exists(file: String) -> bool:
	return FileAccess.file_exists(file)

## Reads the file; a missing file is an empty account list. Returns false
## (last_error says why) for a file that cannot be used, so the server refuses
## to start instead of overwriting it.
func load_file() -> bool:
	last_error = ""
	if not FileAccess.file_exists(path):
		data = {"version":VERSION,"allow_create":true,"profiles":[]}
		_loaded_mtime = -1
		return true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("profiles",[]) is Array:
		last_error = "账号文件 %s 无法读取。" % ProjectSettings.globalize_path(path)
		return false
	var problem := _validate(parsed)
	if not problem.is_empty():
		last_error = "账号文件 %s：%s" % [ProjectSettings.globalize_path(path),problem]
		return false
	data = parsed
	data.version = VERSION
	if not data.has("allow_create"):data.allow_create = true
	for entry in data.profiles:
		if not entry.has("tokens"):entry.tokens = []
		entry.admin = bool(entry.get("admin",false))
	_loaded_mtime = FileAccess.get_modified_time(path)
	return true

## Picks up edits made with scripts/accounts.sh while the server runs.
func reload_if_changed() -> void:
	if path.is_empty() or not FileAccess.file_exists(path):return
	if FileAccess.get_modified_time(path)==_loaded_mtime:return
	var before := data
	if not load_file():
		printerr(last_error)
		data = before

func _validate(value: Dictionary) -> String:
	var ids := {}
	var names := {}
	var saves := {}
	for entry in value.get("profiles",[]):
		if not entry is Dictionary:return "条目格式不对"
		for field in ["id","name","salt","pin"]:
			if not entry.get(field) is String or str(entry.get(field)).is_empty():return "缺少 %s" % field
		var key := str(entry.name).to_lower()
		if ids.has(entry.id) or names.has(key):return "名字重复：%s" % entry.name
		var save := save_path(entry)
		if saves.has(save):return "两个角色用同一个存档：%s" % save
		ids[entry.id] = true
		names[key] = true
		saves[save] = true
	return ""

## Written to a temporary file and renamed, so a crash never leaves half a file.
func save_file() -> bool:
	if path.is_empty():return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data,"  "))
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:return false
	_loaded_mtime = FileAccess.get_modified_time(path)
	return true

func profiles() -> Array:
	return data.get("profiles",[])

## The profile named `name` (case-insensitive), or {}.
func find(name: String) -> Dictionary:
	var key := name.strip_edges().to_lower()
	for entry in profiles():
		if str(entry.name).to_lower()==key:return entry
	return {}

func by_id(id: String) -> Dictionary:
	for entry in profiles():
		if str(entry.id)==id:return entry
	return {}

func is_admin(id: String) -> bool:
	return bool(by_id(id).get("admin",false))

func allow_create() -> bool:
	return bool(data.get("allow_create",true))

## The profile's save: its own `save`, else <accounts folder>/<id>.json.
func save_path(entry: Dictionary) -> String:
	var own := str(entry.get("save",""))
	if not own.is_empty():return own
	return path.get_base_dir().path_join(str(entry.id)+".json")

## For the profile picker: [{name, admin}] in file order.
func listing() -> Array:
	var result: Array = []
	for entry in profiles():result.append({"name":str(entry.name),"admin":bool(entry.admin)})
	return result

static func hash_pin(salt: String, pin: String) -> String:
	return (salt+":"+pin).sha256_text()

static func random_hex(bytes: int = 16) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()

## "" when `name` can name a character, else why not.
static func name_problem(name: String) -> String:
	var clean := name.strip_edges()
	if clean.is_empty():return "请输入角色名。"
	if clean.length() > NAME_LENGTH:return "角色名最多 %d 个字。" % NAME_LENGTH
	for i in range(clean.length()):
		if clean.unicode_at(i) < 32:return "角色名不能含控制字符。"
	return ""

## "" when `pin` is 4 to 8 digits, else why not.
static func pin_problem(pin: String) -> String:
	if pin.length() < 4 or pin.length() > 8 or not pin.is_valid_int() or pin.begins_with("-") or pin.begins_with("+"):return "PIN 须为 4 到 8 位数字。"
	return ""

## A file-safe id: the name itself when it is plain ASCII, else p1, p2 ...
func _new_id(name: String) -> String:
	var slug := name.strip_edges().to_lower()
	var regex := RegEx.create_from_string("^[a-z0-9_-]{1,32}$")
	if regex.search(slug)!=null and by_id(slug).is_empty():return slug
	var n := 1
	while not by_id("p%d" % n).is_empty():n += 1
	return "p%d" % n

## Adds a profile. The first profile, or any while no admin exists, is the
## admin (the owner) unless `admin` says otherwise. {ok, entry} or {ok:false,
## reason}. `from_client` respects allow_create.
func create(name: String, pin: String, from_client: bool = true, admin: Variant = null, save: String = "") -> Dictionary:
	var problem := name_problem(name)
	if problem.is_empty():problem = pin_problem(pin)
	if problem.is_empty() and not find(name).is_empty():problem = "角色名「%s」已被使用。" % name.strip_edges()
	if problem.is_empty() and from_client and not allow_create():problem = "这台服务器不允许新建角色，请找管理员添加。"
	if problem.is_empty() and profiles().size() >= MAX_PROFILES:problem = "角色数已达上限 %d。" % MAX_PROFILES
	var entry := {"id":_new_id(name),"name":name.strip_edges(),"admin":false,"tokens":[],"created":int(clock.call())}
	if not save.is_empty():entry.save = save
	if problem.is_empty():
		for other in profiles():
			if save_path(other)==save_path(entry):problem = "存档 %s 已属于「%s」。" % [save_path(entry),other.name]
	if not problem.is_empty():return {"ok":false,"reason":problem}
	var has_admin := profiles().any(func(other):return bool(other.admin))
	entry.admin = bool(admin) if admin!=null else not has_admin
	entry.salt = random_hex()
	entry.pin = hash_pin(entry.salt,pin)
	profiles().append(entry)
	if not save_file():
		profiles().erase(entry)
		return {"ok":false,"reason":"无法写入账号文件。"}
	return {"ok":true,"entry":entry}

## Seconds until `id` may try a PIN again, 0 when it may now.
func locked_for(id: String) -> int:
	var record: Dictionary = _failures.get(id,{})
	return maxi(0,ceili(float(record.get("until",0.0))-float(clock.call())))

## Checks a PIN. {ok, entry} or {ok:false, reason, locked (seconds)}.
func verify_pin(name: String, pin: String) -> Dictionary:
	var entry := find(name)
	if entry.is_empty():return {"ok":false,"reason":"没有叫「%s」的角色。" % name.strip_edges()}
	var id := str(entry.id)
	var wait := locked_for(id)
	if wait > 0:return {"ok":false,"reason":"PIN 连续输错 %d 次，请 %s 后再试。" % [MAX_FAILURES,_duration(wait)],"locked":wait}
	if hash_pin(str(entry.salt),pin)==str(entry.pin):
		_failures.erase(id)
		return {"ok":true,"entry":entry}
	var record: Dictionary = _failures.get(id,{"count":0,"until":0.0})
	record.count = int(record.count)+1
	if int(record.count) >= MAX_FAILURES:
		record.count = 0
		record.until = float(clock.call())+LOCK_SECONDS
		_failures[id] = record
		return {"ok":false,"reason":"PIN 连续输错 %d 次，请 %s 后再试。" % [MAX_FAILURES,_duration(LOCK_SECONDS)],"locked":LOCK_SECONDS}
	_failures[id] = record
	return {"ok":false,"reason":"PIN 不对，还可以再试 %d 次。" % (MAX_FAILURES-int(record.count))}

static func _duration(seconds: int) -> String:
	return "%d 分钟" % ceili(seconds/60.0) if seconds >= 60 else "%d 秒" % seconds

## A new device token for `id`; the file keeps its hash.
func issue_token(id: String) -> String:
	var entry := by_id(id)
	if entry.is_empty():return ""
	var token := random_hex()
	var tokens: Array = entry.get("tokens",[])
	tokens.append(token.sha256_text())
	while tokens.size() > MAX_TOKENS:tokens.pop_front()
	entry.tokens = tokens
	save_file()
	return token

## A remembered device: {ok, entry} or {ok:false, reason}.
func verify_token(name: String, token: String) -> Dictionary:
	var entry := find(name)
	if entry.is_empty() or token.is_empty() or not token.sha256_text() in entry.get("tokens",[]):
		return {"ok":false,"reason":"这台设备的登录已失效，请重新输入 PIN。"}
	return {"ok":true,"entry":entry}

## Forgets one device's token (退出登录).
func revoke_token(id: String, token: String) -> void:
	var entry := by_id(id)
	if entry.is_empty() or token.is_empty():return
	var tokens: Array = entry.get("tokens",[])
	if token.sha256_text() in tokens:
		tokens.erase(token.sha256_text())
		save_file()

## A new PIN (scripts/accounts.sh); every remembered device must log in again.
func set_pin(name: String, pin: String) -> String:
	var entry := find(name)
	if entry.is_empty():return "没有叫「%s」的角色。" % name
	var problem := pin_problem(pin)
	if not problem.is_empty():return problem
	entry.salt = random_hex()
	entry.pin = hash_pin(entry.salt,pin)
	entry.tokens = []
	_failures.erase(str(entry.id))
	return "" if save_file() else "无法写入账号文件。"
