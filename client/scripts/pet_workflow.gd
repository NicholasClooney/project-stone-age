extends Node
## Local capture/train cycles. Stat failures store and repeat; a match stops for comparison.
## Battle actions and rewards stay with existing authorities. The cycle itself
## runs in the backend (res://server/automation.gd); this node starts, stops and
## presents it.
const StatFilter=preload("res://scripts/pet_stat_filter.gd")
const Automation=preload("res://server/automation.gd")
var world: Node

func configure(owner: Node) -> void:world=owner

func _flow() -> Dictionary:
	return world.state.automation.get("flow",{}) if is_instance_valid(world) else {}

## In-process test seam: write backend workflow fields directly.
func _seam(fields: Dictionary) -> void:
	world.link.request({"type":"auto","name":"set","fields":fields})

var phase: String:
	get:return str(_flow().get("phase","idle"))
	set(value):_seam({"flow_phase":value})
var reason: String:
	get:return str(_flow().get("reason",""))
	set(value):_seam({"flow_reason":value})
var pet_id: String:
	get:return str(_flow().get("pet_id",""))
	set(value):_seam({"flow_pet_id":value})
## In-process reads come straight from the runner; a remote client reads status.
func _live(field: String, key: String) -> Variant:
	if world.link.is_local():return world.backend.automation.get(field)
	return _flow().get(key)

var stored_count: int:
	get:return int(_live("flow_stored_count","stored_count"))
	set(value):_seam({"flow_stored_count":value})
var last_result: String:
	get:return str(_live("flow_last_result","last_result"))
	set(value):_seam({"flow_last_result":value})
var last_stored_id: String:
	get:return str(_live("flow_last_stored_id","last_stored_id"))
	set(value):_seam({"flow_last_stored_id":value})
var last_stored_total: int:
	get:return int(_live("flow_last_stored_total","last_stored_total"))
	set(value):_seam({"flow_last_stored_total":value})
var kept_count: int:
	get:return int(_live("flow_kept_count","kept_count"))
	set(value):_seam({"flow_kept_count":value})
var collected_count: int:
	get:return int(_live("flow_collected_count","collected_count"))
	set(value):_seam({"flow_collected_count":value})
var pruned_count: int:
	get:return int(_live("flow_pruned_count","pruned_count"))
	set(value):_seam({"flow_pruned_count":value})
## 保留规则 auto tidy: pets it released this run, and the species count left.
var released_count: int:
	get:return int(_live("flow_released_count","released_count"))
	set(value):_seam({"flow_released_count":value})
var held_count: int:
	get:
		return int(_live("flow_held_count","held_count"))
var keep_auto: bool:
	get:
		if world.link.is_local():return bool(world.backend.automation.flow_target_filter.get("keep_rule",{}).get("auto",false))
		return bool(_flow().get("keep_auto",false))
## Hits the cycle stepped past (capture failed, a queued roll no longer
## verified) and the latest such note; see 停止记录 in 宠物记录.
var skipped_count: int:
	get:return int(_live("flow_skipped_count","skipped_count"))
var skip_note: String:
	get:return str(_live("flow_skip_note","skip_note"))
var predicted_rejects: int:
	get:return int(_live("flow_predicted_rejects","predicted_rejects"))
	set(value):_seam({"flow_predicted_rejects":value})
var best_predicted: Dictionary:
	get:
		var best = _live("flow_best_predicted","best_predicted")
		return best if best is Dictionary else {}
	set(value):_seam({"flow_best_predicted":value})
## In-process test seam: the clock the workflow timer reads.
var timer_clock: Callable:
	get:return world.backend.automation.timer_clock
	set(value):world.backend.automation.timer_clock = value

func elapsed_seconds() -> float:
	if world.link.is_local():return world.backend.automation.elapsed_seconds()
	return float(_flow().get("elapsed",0.0))
func elapsed_text() -> String:
	var seconds:=int(elapsed_seconds())
	return "%02d:%02d:%02d" % [seconds/3600,(seconds/60)%60,seconds%60]
func collect_target_text() -> String:
	if world.link.is_local():return world.backend.automation.collect_target_text()
	return str(_flow().get("collect_target","1"))
## In-process test seam onto the hunt-time Lv.120 prediction gate.
func accepts_prediction(actor: Dictionary) -> bool:
	return world.backend.automation.accepts_prediction(actor)
## In-process test seams onto the running cycle's filters.
var target_stat_filter: Dictionary:
	get:return world.backend.automation.flow_target_filter
	set(value):world.backend.automation.flow_target_filter = value
var stat_filter_snapshot: Dictionary:
	get:return world.backend.automation.flow_stat_filters

func active() -> bool:return phase in ["hunt","capture","train","restart"]

func start_cycle(species_key: String="") -> bool:
	if active():return false
	if world.battle_session.snapshot().get("active",false) or world.battle_view.visible or world.moving or world.area_transition_busy:
		world.message.text="请先结束战斗或移动，再开始一轮找宠。";return false
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		world.message.text="宠物栏已满，请自行存放伙伴后再开始。";return false
	world.pet_hunt_menu.commit_stat_settings()
	world.adventure_menu.hide();world.paused_input=false
	if not world.pet_hunt_menu.visible:world.pet_hunt_menu.open_menu()
	if not species_key.is_empty():
		var template_id:=92 if species_key=="blue" else int(species_key.trim_prefix("original_"))
		if not world.pet_hunt_menu.choose_target(template_id):
			stop_cycle("当前地点和等级条件没有此品种；请自行前往合适地点或调整找宠条件。");return false
	# Starting from the already-open hunt panel must retain its modal lock.
	world.clear_input();world.paused_input=true
	var filter: Dictionary=world.pet_hunt_menu.build_filter(true)
	if filter.is_empty():
		stop_cycle(world.pet_hunt_menu.status.text);return false
	# The backend runs with the profile's hunt, capture and stat settings.
	world.pet_hunt_menu.commit_settings()
	var command:={"type":"auto_start","kind":"find_pet","map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]}
	if not world.pet_hunt_menu.start_filter().is_empty():command.filter=world.pet_hunt_menu.start_filter()
	var reply: Dictionary=world.link.request(command)
	if not reply.ok and not reply.get("pending",false):
		world.message.text="找宠流程暂停："+str(reply.reason);return false
	world.pet_hunt_menu.set_controls(true);world.pet_hunt_menu.update_status()
	return true

## Stops the cycle at once, or with `now` false (the player's 停止) after
## the pet being caught or trained is finished.
func stop_cycle(message: String="已手动停止", now: bool = true) -> void:
	world.link.request({"type":"auto","name":"stop_flow","reason":message,"now":now})

## A stop waits for the pet being caught or trained ("" when none).
func stop_pending() -> String:
	return str(world.state.automation.get("flow",{}).get("stop_pending",""))

func _process(_delta: float) -> void:
	# In-process, this frame drives the backend cycle. Over a network the
	# backend checks the reported position itself, and other devices (still
	# following, or loading the map) must not stop a shared run.
	if world.link.is_local():advance()

## One backend workflow step, after checking this client's own position.
func advance() -> void:
	if not active():return
	if _moved():
		stop_cycle("位置发生变化；请在当前位置重新开始。");return
	world.link.request({"type":"auto","name":"flow_step"})

func _moved() -> bool:
	var origin: Array=_flow().get("cell",[0,0])
	return int(world.data.map_id)!=int(_flow().get("map_id",-1)) or world.cell!=Vector2i(int(origin[0]),int(origin[1])) or world.moving or world.area_transition_busy

func complete_trained_pet(found: Dictionary) -> void:
	world.link.request({"type":"auto","name":"complete_trained_pet","found":found})

## Test seam for a map rebuild; the game reports real rebuilds itself.
func prepare_scene_reload() -> String:
	return str(world.link.request({"type":"auto","name":"scene_reload"}).get("paused",""))

static func same_capture(pet: Dictionary, actor: Dictionary) -> bool:
	return Automation.same_capture(pet,actor)

## 后台搜宠: the info block, and the music back to the radio or the map once
## the run ends. Watched battles play at this device's own 战斗速度.
func on_status(automation: Dictionary) -> void:
	if is_instance_valid(world.showcase_ticker):world.showcase_ticker.on_status(automation)
	if world.showcase_music and not world.showcase_music_active():world.end_showcase_music()

func on_event(detail: Dictionary) -> void:
	match str(detail.kind):
		"flow_hunt":
			# Minimized, each new round keeps going behind whatever the player has open.
			if world.pet_hunt_menu.minimized:return
			world.adventure_menu.hide();world.paused_input=false
			if not world.pet_hunt_menu.visible:world.pet_hunt_menu.open_menu()
			world.clear_input();world.paused_input=true
		"flow_reveal":
			# 后台搜宠 clears the stage: the hunt window folds to its progress bar
			# (展开 brings it back). A pet window the player opened stays: it
			# works over the capture and training battles.
			if world.pet_hunt_menu.visible and not world.pet_hunt_menu.minimized:world.pet_hunt_menu.minimize()
		"flow_paused":
			world.message.text="找宠流程暂停："+str(detail.reason)
		"flow_skipped":
			world.refresh_companion()
			world.message.text=str(detail.get("note",detail.reason))
		"flow_stored":
			world.refresh_companion()
			world.message.text=str(detail.result)
		"flow_compare":
			world.paused_input=true
			world.adventure_menu.open_pet_comparison(pet_id)
			world.message.text=str(detail.reason)
