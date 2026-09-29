extends RefCounted
## Backend automation: auto battles (attack, capture, pet training), hunt
## scanning and the find-pet workflow. These run on the backend tick whether or
## not a client is attached. Settings come from the character profile
## (scripts/automation_settings.gd); clients start runs and present status and
## events. Ported from the former client loops without rule changes.
const GameSession = preload("res://server/game_session.gd")
const Policy = preload("res://scripts/battle_auto_policy.gd")
const Progression = preload("res://server/progression.gd")
const HuntRules = preload("res://scripts/pet_hunt_rules.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const KeepRule = preload("res://scripts/keep_rule.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const TroopArt = preload("res://server/troop_art.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const Rarity = preload("res://scripts/showcase_rarity.gd")
const ReleaseLog = preload("res://server/release_log.gd")
## A presenting client may slow automation to its animation, never stall it.
const PRESENT_TIMEOUT_MSEC := 5000
const HUNT_FRAME_BUDGET_USEC := 12000
const COMPACT_BUDGET_USEC := 12000
const HUNT_MAX_BACKLOG_SECONDS := 0.1
## Pace of an uncompacted run when the starting device names no playback speed.
const DEFAULT_SPEED := 8.0

var backend
## Tests drive step() themselves when false.
var auto_tick := true
## False when no client presents battles; paced waits are then skipped.
var client_attached := true
var position_map := -1
var position_cell := Vector2i.ZERO

# ---- battle runner ---------------------------------------------------------
var running := false
## The current run's flat settings: the profile's effective training and
## capture settings, the starting device's playback speed and run-only forcing.
var settings: Dictionary = {"speed":DEFAULT_SPEED}
var single_battle := false
var capture_target := -1
var training_pet_id := ""
var training_pet_level := 120
var finish_after_capture := false
var clone_override_active := false
var previous_clone_enabled := false
var compact_active := false
var battles := 0
var skipped := 0
var unavailable_streak := 0
var earned_xp := 0
var earned_pet_xp := 0
var turns := 0
var cooldown := 0.0
var origin_map := -1
var origin_cell := Vector2i.ZERO
var initial_level := 1
var stop_reason := ""
var starting_ride := -1
var turn_text := ""
var _presented_key := ""
var _shown_key := ""
var _shown_msec := 0

# ---- hunt scanning ---------------------------------------------------------
var hunt_running := false
var hunt_filter: Dictionary = {}
var hunt_catalog
var hunt_map := -1
var hunt_cell := Vector2i.ZERO
var hunt_rolls := 0
var hunt_inspected := 0
var hunt_best := -9
var hunt_elapsed := 0.0
var hunt_credit := 0.0
var hunt_started_usec := 0
var hunt_last_hit: Dictionary = {}
var hunt_status := ""
## Every roll of a run has its own seed (FastHunt.roll_seed(hunt_run_seed, i)),
## so the native helper can scan rolls in parallel and a roll can be replayed.
var hunt_run_seed := 0
var hunt_rng := RandomNumberGenerator.new()
## 本机极速模式: wanted by the hunt settings (hunt.fast), and whether the helper
## is scanning now. hunt_fast_note says why it is not, when wanted.
var fast_hunt := FastHunt.new()
var hunt_fast_wanted := false
var hunt_fast_note := ""
var _fast_base: Dictionary = {}
## Why this backend cannot run the helper ("" when it can), for the hunt window.
var fast_unavailable := FastHunt.unavailable_reason()
## 线程数 for the helper, the server's own setting (server_settings.gd; 0 = auto).
var fast_threads := ServerSettings.fast_hunt_threads()

# ---- find-pet workflow -----------------------------------------------------
var flow_phase := "idle"
var flow_reason := ""
var flow_pet_id := ""
var flow_map := -1
var flow_cell := Vector2i.ZERO
var flow_known_ids: Dictionary = {}
var flow_matched_actor: Dictionary = {}
var flow_matched_index := -1
var flow_capture_battle_id := ""
var flow_stat_filters: Dictionary = {}
## Profile overrides when the cycle started, for species not in flow_stat_filters.
var flow_settings_overrides: Dictionary = {}
var flow_target_filter: Dictionary = {}
var flow_hunt_request: Dictionary = {}
var flow_stored_count := 0
var flow_last_result := ""
var flow_last_stored_id := ""
var flow_last_stored_total := 0
# With a filter's stop_after other than 1, matches are stored and the hunt goes
# on until this run keeps stop_after of them (0 = until stopped manually).
var flow_kept_count := 0
var flow_collected_count := 0
var flow_pruned_count := 0
# Rejects stored by this run; rolling keep only ever prunes among these.
var flow_run_reject_ids: Array = []
# 保留规则 with 找宠时自动整理 (the filter's keep_rule.auto): pets it released
# this run, and how many of the species remain after the last tidy.
var flow_released_count := 0
var flow_held_count := 0
var flow_predicted_rejects := 0
## 抓宠记录 groups captures by find-pet run: set when a new (not continuing)
## cycle starts and kept across its restarts.
var flow_run_id := ""
## 后台搜宠 (hunt.showcase, default on; the name players see is
## AutomationSettings.SHOWCASE_NAME): the find-pet cycle keeps searching while
## the player watches a found pet's capture and 自动练级 to Lv.120; hits wait in
## `showcase_queue` (hunt.queue long). Off, the cycle runs as before.
const SHOWCASE_QUEUE_MAX := 10
const SHOWCASE_LOG_MAX := 8
## A watching device plays a shown battle at its own speed; the runner waits
## for its turn to finish playing up to this long (a 1x group turn is long).
const SHOWN_PRESENT_TIMEOUT_MSEC := 60000
var flow_showcase := false
## Found hits waiting for their turn: {index, slot, run_seed, actor, troop,
## prediction, quality}, best first by the species' ranking.
var showcase_queue: Array = []
var showcase_current: Dictionary = {}
## The battle now open is one the player watches (not compact).
var showcase_show_battle := false
## The info block's lines: {id, kind, text}, newest last.
var showcase_log: Array = []
var _showcase_log_serial := 0
var _flow_run_serial := 0
## 停止记录: every stop, pause and skip of the hunt and the find-pet cycle,
## drained by the backend into <save>.stop-log.jsonl (server/release_log.gd).
var stop_events: Array = []
## A failure the cycle can step past (see _skip_hit) skips the current hit;
## the same kind SKIP_LIMIT times in a row stops the cycle instead.
const SKIP_LIMIT := 3
## Why a capture battle ended without its pet when the cycle may simply try
## the next hit; any other runner stop needs the player.
const SKIPPABLE_BATTLE_STOPS := ["捕捉目标已倒下，已停止；不会改抓其他敌人","当前战斗不可继续捕捉，可能已达捕获数量上限","战斗未获胜","单场超过200回合，请手动处理","找不到可攻击目标"]
var flow_skip_kind := ""
var flow_skip_streak := 0
var flow_skipped_count := 0
var flow_skip_note := ""
var _stopping_cycle := false
var flow_best_predicted: Dictionary = {}
## 最高 − x thresholds (pet_stat_filter.gd resolve): per species, the best Lv120
## values among the player's own pets, recomputed when pet_signature changes;
## pets a survey picked and the cycle is about to catch count as well.
var _owned_maxima: Dictionary = {}
var _pets_key := ""
## The resolved thresholds the native helper was launched with; a change (a
## better pet arrived) restarts it with the new ones.
var _fast_thresholds := ""
## Set by request_stop_cycle: the cycle stops once this pet is trained.
var flow_stop_pending := ""
## 摸底: a species with enabled conditions and no pet of its own has no 最高 to
## count from. The cycle then scans that species with no threshold for
## survey_seconds of wall time, collecting candidates (pool kept by the
## species' 保留规则, as the helper does), replays them, and catches what the
## keep rule would keep of them. After that the thresholds roll as usual.
var survey_seconds: int = AutomationSettings.SURVEY_SECONDS
var survey_clock: Callable = Time.get_ticks_msec
## {} or {templates: [ids], started: msec, candidates: key -> candidate,
## runs: [run seeds in order]}; a candidate is {run_seed, index, slot,
## template_id, prediction, serial}.
var survey: Dictionary = {}
## Survey picks waiting for their capture when 后台搜宠 is off (with it on
## they wait in showcase_queue, marked survey).
var survey_picks: Array = []
## The last survey's result for the status: {candidates, picked, text}.
var survey_last: Dictionary = {}
## The pet the cycle is catching was picked by a survey: it counts as found.
var flow_target_survey := false
var timer_clock: Callable = Time.get_ticks_msec
var timer_started_msec := 0
var timer_frozen_seconds := 0.0
var timer_running := false

func _init(owner) -> void:
	backend = owner

# ---- commands --------------------------------------------------------------

func start(command: Dictionary) -> Dictionary:
	_set_position(command)
	match str(command.get("kind","")):
		"battle":return _start_battle_runner(command)
		"capture_battle":
			_set_speed(command)
			return _reply(start_capture_battle(int(command.get("target",-1)),bool(command.get("finish_battle",false)),command.get("settings",{})),stop_reason)
		"pet_train":
			_set_speed(command)
			return _reply(start_pet_training(str(command.get("pet_id","")),int(command.get("target_level",120)),command.get("settings",{})),stop_reason)
		"hunt":
			if hunt_running or running or flow_active():return _reply(false,"自动流程进行中")
			_load_settings(command)
			return _reply(start_hunt(hunt_request(command)),hunt_status)
		"find_pet":
			if flow_active():return _reply(false,"找宠流程进行中")
			# A cycle keeps the stat conditions it started with. Older clients may
			# still send their own; the profile's are used otherwise.
			flow_settings_overrides = backend.session.automation_settings()
			flow_stat_filters = AutomationSettings.stat_filters(flow_settings_overrides)
			flow_stat_filters.merge(_int_keys(command.get("stat_filters",{})),true)
			flow_hunt_request = hunt_request(command)
			_load_settings(command)
			return _reply(start_cycle(false),flow_reason)
	return {"ok":false,"reason":"unknown automation"}

## The run's settings from the profile, the device's playback speed and any
## run-only `settings` a command still carries (older clients, tests).
func _load_settings(command: Dictionary = {}) -> void:
	var speed := float(settings.get("speed",DEFAULT_SPEED))
	settings = profile_settings()
	settings.speed = speed
	_set_speed(command)
	if command.get("settings") is Dictionary:settings.merge(command.settings,true)

func profile_settings() -> Dictionary:
	return AutomationSettings.runner_settings(backend.session.automation_settings(),int(backend.session.snapshot().player.level))

func _set_speed(command: Dictionary) -> void:
	if command.has("speed"):settings.speed = clampf(float(command.speed),1.0,8.0)

## Hunt filter from the profile plus the templates this backend can present
## here; a command's own `filter` (older clients, tests) overrides fields.
func hunt_request(command: Dictionary = {}) -> Dictionary:
	var filter: Dictionary = AutomationSettings.hunt_filter(backend.session.automation_settings())
	var given = command.get("filter",{})
	if given is Dictionary:filter.merge(given,true)
	if not filter.has("usable"):filter.usable = usable_templates(bool(filter.level_one))
	return filter

## Capturable templates at the reported position whose art this backend has.
func usable_templates(level_one: bool) -> Array:
	var usable := []
	for item in HuntRules.candidates(backend.encounter_catalog,position_map,position_cell,level_one):
		var definition: Dictionary = backend.encounter_catalog.data.get("templates",{}).get(str(item.id),{})
		if TroopArt.can_render([{"sprite":int(definition.get("sprite",-1))}]):usable.append(int(item.id))
	return usable

## The profile's automation settings changed: a running capture follows the
## new capture settings at once (training settings apply from the next start).
func profile_settings_changed() -> void:
	if not (running or hunt_running or flow_active()):return
	var fresh := profile_settings()
	for key in ["capture_hp","capture_pet","capture_pet_id","capture_pet_max_level"]:settings[key] = fresh[key]
	_emit_status()

func update(command: Dictionary) -> Dictionary:
	if command.has("settings"):settings.merge(command.settings,true)
	if command.has("stat_filters"):flow_stat_filters = _int_keys(command.stat_filters)
	_emit_status()
	return {"ok":true}

func stop_request(reason: String) -> Dictionary:
	if flow_active():stop_cycle(reason)
	elif running:stop(reason)
	if hunt_running:stop_hunt(reason)
	return {"ok":true}

func command(name: String, arguments: Dictionary) -> Dictionary:
	match name:
		"stop_battle":
			if running:stop(str(arguments.get("reason","已手动停止")))
		"stop_hunt":
			if hunt_running:stop_hunt(str(arguments.get("reason","已停止")))
		"stop_flow":
			if bool(arguments.get("now",false)):stop_cycle(str(arguments.get("reason","已手动停止")))
			else:request_stop_cycle(str(arguments.get("reason","已手动停止")))
		"acquire_clone":acquire_clone_override()
		"release_clone":release_clone_override()
		"flow_step":flow_step()
		"hunt_scan":scan_once()
		"tick_battle":tick_battle(float(arguments.get("delta",0.0)))
		"complete_trained_pet":complete_trained_pet(arguments.get("found",{}))
		"scene_reload":return {"ok":true,"paused":position_changed(position_map,position_cell,true)}
		"hunt_process":
			if hunt_running:_hunt_process(float(arguments.get("delta",0.0)))
		"set":
			for key in arguments.get("fields",{}):set(key,arguments.fields[key])
			_emit_status()
	return {"ok":true}

func presented(battle_id: String, turn: int) -> void:
	_presented_key = "%s:%d" % [battle_id,turn]

func position_changed(map_id: int, cell: Vector2i, map_changed: bool = false) -> String:
	position_map = map_id
	position_cell = cell
	if not map_changed:return ""
	# A new map ends the current run; a defeat or travel pauses the workflow.
	var pause := ""
	if flow_active():
		pause = "战斗失败，流程已暂停。" if str(backend.battle.snapshot().get("outcome",""))=="defeat" else "地图发生变化，流程已暂停。"
		_record_stop("flow","暂停",pause,_involved_pet())
		freeze_timer()
		flow_phase = "paused"
		flow_reason = pause
	if hunt_running and pause.is_empty():_record_stop("hunt","停止","地图发生变化，筛选已停止。")
	hunt_running = false
	release_clone_override()
	running = false
	compact_active = false
	backend.set_capture_assist(false)
	_emit_status()
	return pause

# ---- tick ------------------------------------------------------------------

## Standalone backend tick. An in-process client drives the same three parts
## from its frame loop instead (tick_battle, hunt_process, flow_step).
func tick(delta: float) -> void:
	if not auto_tick:return
	tick_battle(delta)
	if hunt_running:_hunt_process(delta)
	if flow_active():flow_step()

func tick_battle(delta: float) -> void:
	if not running:return
	# Compact battles have nothing to watch: run steps back to back within a frame budget.
	if bool(settings.compact) and (compact_active or not backend.battle_open):
		var until := Time.get_ticks_usec()+COMPACT_BUDGET_USEC
		while running and (compact_active or not backend.battle_open) and Time.get_ticks_usec()<until:step()
		return
	cooldown -= delta
	if cooldown > 0:return
	cooldown = 0.25/float(settings.speed)
	step()

## One battle-runner step.
func step() -> void:
	if not running:return
	if position_map!=origin_map or position_cell!=origin_cell:
		stop("位置发生变化");return
	var state: Dictionary = backend.battle.snapshot()
	if backend.battle_open:
		if not compact_active and not _presentation_done(state):return
		if not state.active:
			battles += 1
			turns = 0
			var outcome: String = state.outcome
			_close_battle()
			if outcome=="defeat":
				# Defeat returns the player to the village and ends the run. An
				# attached client reports that arrival itself.
				if not client_attached:
					var pause := position_changed(backend.VILLAGE.map_id,Vector2i(backend.VILLAGE.x,backend.VILLAGE.y),true)
					if not pause.is_empty():_emit_event({"kind":"flow_paused","reason":pause})
				release_clone_override()
				running = false
				stop_reason = "战斗失败"
				_emit_status()
				return
			_emit_status()
			if outcome not in ["win","captured"]:stop("战斗未获胜");return
			if single_battle:stop("本场自动战斗已完成");return
			return
		var reason := health_reason(state)
		if not reason.is_empty():stop(reason);return
		if turns >= 200:stop("单场超过200回合，请手动处理");return
		if str(settings.preset)=="capture" and backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
			stop("宠物栏已满，请先腾出位置");return
		if str(settings.preset)=="capture" and finish_after_capture and capture_target>=0 and capture_target<state.enemies.size() and state.enemies[capture_target].get("captured",false):
			settings.preset = "attack"
		var decision: Dictionary = Policy.decide(state,settings,capture_target)
		if decision.has("stop"):stop(str(decision.stop));return
		backend.set_capture_assist(str(settings.preset)=="capture")
		backend.battle.set_pet_command(str(decision.pet))
		var next: Dictionary = backend.battle_command({"action":str(decision.action),"target":int(decision.target),"pet_target":int(decision.target),"switch_pet":int(decision.get("switch",-2))})
		turns += 1
		if next.get("settled",false):record_result(next)
		turn_text = "第 %d 回合 · 体力 %d/%d\n%s" % [turns,next.player_hp,next.player_max_hp," / ".join(next.events)]
		_emit_status()
		return
	if backend.session.heal_carried_pets():
		backend.save()
		backend.publish()
	var p: Dictionary = backend.session.snapshot()
	if not training_pet_id.is_empty():
		var selected := -1
		for i in range(p.pets.size()):
			if str(p.pets[i].get("pet_id",""))==training_pet_id:selected = i;break
		if selected < 0:stop("目标宠物不在随身队伍");return
		if selected!=int(p.active_pet):stop("目标宠物不再出战");return
		if int(p.pets[selected].level)>=training_pet_level:stop("目标宠物已达到等级目标");return
	if int(settings.level) > 0 and int(p.player.level)>=int(settings.level):stop("已达到目标等级");return
	if battles>=int(settings.limit):stop("已达到战斗场次上限");return
	var reason := profile_health_reason()
	if not reason.is_empty():stop(reason);return
	compact_active = bool(settings.compact)
	_emit_status()
	var opened: Dictionary = backend.wild_encounter(origin_map,origin_cell) if backend.session.world_catalog.field(origin_map) else {"ok":false,"skipped":""}
	if not opened.ok:
		compact_active = false
		if str(opened.get("skipped",""))=="art":
			skipped += 1
			unavailable_streak += 1
			turn_text = "该敌群原版素材不可用，已跳过，无奖励。"
			if unavailable_streak >= 100:stop("连续100组缺素材，请更换区域")
			else:_emit_status()
			return
		stop("当前位置遇敌数据或条件不可用，请换个位置");return
	unavailable_streak = 0
	var battle_state: Dictionary = backend.battle.snapshot()
	starting_ride = int(battle_state.get("ride_pet",-1))
	capture_target = -1
	if str(settings.preset)=="capture":
		for i in range(battle_state.enemies.size()):
			if battle_state.enemies[i].get("can_capture",false) and int(battle_state.enemies[i].hp) > 0:capture_target = i;break
	backend.set_capture_assist(str(settings.preset)=="capture")
	_emit_status()

func _presentation_done(state: Dictionary) -> bool:
	if not client_attached:return true
	var key := "%s:%d" % [str(state.get("battle_id","")),int(state.get("turn",0))]
	if key==_presented_key:return true
	if key!=_shown_key:
		_shown_key = key
		_shown_msec = Time.get_ticks_msec()
	return Time.get_ticks_msec()-_shown_msec >= (SHOWN_PRESENT_TIMEOUT_MSEC if showcase_show_battle else PRESENT_TIMEOUT_MSEC)

func _close_battle() -> void:
	compact_active = false
	if backend.battle_open:backend.close_battle()

# ---- battle runner lifecycle -----------------------------------------------

func _start_battle_runner(command: Dictionary) -> Dictionary:
	_set_position(command)
	_load_settings(command)
	if command.has("capture_target"):capture_target = int(command.capture_target)
	start_training()
	return _reply(running,stop_reason)

func start_training() -> void:
	training_pet_id = ""
	finish_after_capture = false
	backend.session.experience_multiplier = int(settings.xp)
	single_battle = bool(backend.battle.snapshot().active) and backend.battle_open
	if not single_battle and not backend.session.world_catalog.field(position_map):
		stop_reason = "请先到野外再开始自动练级。"
		_emit_event({"kind":"battle_refused","reason":stop_reason})
		return
	origin_map = position_map
	origin_cell = position_cell
	initial_level = int(backend.session.snapshot().player.level)
	battles = 0;skipped = 0;unavailable_streak = 0;earned_xp = 0;earned_pet_xp = 0;turns = 0;cooldown = 0;stop_reason = "";starting_ride = -1;turn_text = ""
	if str(settings.preset)=="train_pet":
		if single_battle and backend.battle.snapshot().get("allies",[]).is_empty():
			stop_reason = "带宠升级请在遇敌前开启，以生成完整镜像队。"
			_emit_event({"kind":"battle_refused","reason":stop_reason})
			return
		acquire_clone_override()
	backend.set_capture_assist(str(settings.preset)=="capture")
	running = true
	backend.publish()
	_emit_status()

func start_capture_battle(target: int, finish_battle: bool = false, extra: Dictionary = {}) -> bool:
	if not backend.battle.snapshot().active:return false
	_load_settings({"settings":extra})
	capture_target = target
	settings.preset = "capture"
	start_training()
	finish_after_capture = finish_battle
	_emit_status()
	return running

## `overrides` replace the preset's defaults before the first battle opens.
func start_pet_training(pet_id: String, target_level_value: int = 120, extra: Dictionary = {}, overrides: Dictionary = {}) -> bool:
	if running or backend.battle.snapshot().active:return false
	var profile: Dictionary = backend.session.snapshot()
	var chosen := -1
	for i in range(profile.pets.size()):
		if str(profile.pets[i].get("pet_id",""))==pet_id:chosen = i;break
	if chosen < 0:stop_reason = "目标宠物不在随身队伍";return false
	if int(profile.get("ride_pet",-1))==chosen:stop_reason = "目标宠物正在骑乘，请先下骑";return false
	if not backend.session.select_pet(chosen):stop_reason = "无法让目标宠物出战";return false
	backend.publish()
	_load_settings({"settings":extra})
	settings.merge({"preset":"train_pet","speed":8.0,"xp":10,"compact":true,"level":0,"level_explicit":true},true)
	settings.merge(overrides,true)
	start_training()
	if not running:return false
	training_pet_id = pet_id
	training_pet_level = clampi(target_level_value,1,120)
	_emit_status()
	return true

func health_reason(state: Dictionary) -> String:
	if float(state.player_hp)/maxf(1,float(state.player_max_hp))*100<=int(settings.hp):return "玩家体力达到停机线"
	for index in [int(state.get("active_pet",-1)),int(state.get("ride_pet",-1)),starting_ride]:
		if index>=0 and index<state.get("pets",[]).size():
			var pet: Dictionary = state.pets[index]
			if float(pet.hp)/maxf(1,float(pet.max_hp))*100<=int(settings.hp):return "%s 体力达到停机线" % str(pet.get("name","宠物"))
	return ""

func profile_health_reason() -> String:
	var p: Dictionary = backend.session.snapshot()
	return health_reason({"player_hp":p.player.hp,"player_max_hp":p.player.max_hp,"pets":p.pets,"active_pet":p.active_pet,"ride_pet":p.get("ride_pet",-1)})

func stop(reason: String) -> void:
	release_clone_override()
	running = false
	stop_reason = reason
	backend.set_capture_assist(false)
	var takeover := false
	if compact_active and not backend.battle.snapshot().active:
		battles += 1
		_close_battle()
	if compact_active:
		# The battle continues under manual control in the full battle view.
		compact_active = false
		takeover = true
	_emit_status()
	_emit_event({"kind":"battle_stopped","reason":reason,"battles":battles,"takeover":takeover})

func record_result(state: Dictionary) -> void:
	earned_xp += int(state.get("xp",0))
	for amount in state.get("pet_reward_xp",[]):earned_pet_xp += int(amount)

func acquire_clone_override() -> void:
	if not clone_override_active:
		previous_clone_enabled = backend.session.clone_squad_enabled
		clone_override_active = true
	backend.session.clone_squad_enabled = true
	backend.publish()

func release_clone_override() -> void:
	backend.session.clone_best_others = false
	if not clone_override_active:return
	clone_override_active = false
	backend.session.clone_squad_enabled = previous_clone_enabled
	backend.publish()

# ---- hunt scanning ---------------------------------------------------------

## Validates and starts a scan at the reported position. The filter carries the
## client's chosen species set, thresholds, rate and limit.
func start_hunt(filter: Dictionary) -> bool:
	if hunt_running or backend.battle_open:return false
	if not backend.session.world_catalog.field(position_map):return false
	var profile: Dictionary = backend.session.snapshot()
	if profile.pets.size()>=GameSession.PET_CAPACITY:
		hunt_status = "宠物栏已满，请先腾出位置再寻找新伙伴。";return false
	if int(settings.get("capture_hp",100))<100 and bool(filter.get("level_one",true)) and (bool(filter.get("auto_capture",false)) or flow_phase=="hunt"):
		var choice: Dictionary = Policy.capture_pet_choice(profile,settings,1)
		if choice.has("stop"):
			hunt_status = str(choice.stop)
			if int(settings.get("capture_pet",-1))<0 and str(settings.get("capture_pet_id","")).is_empty():hunt_status = "缺少可用削血宠：请从仓库取出存活、非骑乘的Lv.1宠物，或手选符合等级上限的削血宠。"
			_emit_event({"kind":"hunt_refused","reason":hunt_status})
			return false
	if HuntRules.tail_probability(int(filter.get("total",-8)),filter.get("offsets",[-2,-2,-2,-2]))<=0:
		hunt_status = "这些条件无法同时满足，请降低门槛。";return false
	if HuntRules.candidates(backend.encounter_catalog,position_map,position_cell,bool(filter.get("level_one",true))).is_empty():
		hunt_status = "当前区域不会出现符合种类／等级条件的宠物。";return false
	var usable: Array = filter.get("usable",[])
	if usable.is_empty() or (int(filter.get("template",-1))>=0 and not int(filter.template) in usable):
		hunt_status = "当前没有素材齐全的目标宠物。";return false
	hunt_filter = filter.duplicate(true)
	hunt_map = position_map
	hunt_cell = position_cell
	# Freeze the validated location for this run. Only trim the spatial lookup;
	# retain original groups/enemies/templates and all roll checks/RNG calls.
	var hunt_data: Dictionary = backend.encounter_catalog.data.duplicate()
	hunt_data.areas = [backend.encounter_catalog.area_at(hunt_map,hunt_cell)]
	hunt_catalog = EncounterCatalog.new(hunt_data)
	hunt_rolls = 0;hunt_inspected = 0;hunt_best = -9;hunt_elapsed = 0;hunt_credit = 0;hunt_last_hit = {}
	# Two draws from the walking encounter stream seed this run's rolls.
	hunt_run_seed = (backend.encounter_rng.randi() << 32) | backend.encounter_rng.randi()
	hunt_fast_wanted = bool(filter.get("fast",false))
	fast_unavailable = FastHunt.unavailable_reason()
	hunt_fast_note = fast_unavailable if hunt_fast_wanted else ""
	hunt_started_usec = Time.get_ticks_usec()
	hunt_running = true
	hunt_status = ""
	_emit_status()
	return true

func stop_hunt(reason: String) -> void:
	fast_hunt.stop()
	# The find-pet cycle records its own stops; a hit it goes on to capture is none.
	if hunt_running and not flow_active() and not _stopping_cycle:
		_record_stop("hunt","找到" if reason.begins_with("找到达标个体") else "停止",reason)
	hunt_running = false
	hunt_status = reason
	_emit_status()
	_emit_event({"kind":"hunt_stopped","reason":reason})

func _hunt_process(delta: float) -> void:
	var background := flow_showcase and flow_active()
	if (backend.battle_open and not background) or position_map!=hunt_map or position_cell!=hunt_cell:
		stop_hunt("场景状态变化，筛选已停止。");return
	hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
	if _predicting():
		refresh_maxima()
		_survey_process()
		if not hunt_running:return
		if not flow_showcase and not survey_picks.is_empty():
			_take_survey_pick();return
	# Discard old backlog after a stall; never catch up with an unbounded burst.
	# A rate of 0 or less is unlimited: scan for the whole frame budget.
	if _fast_process():
		hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
		if hunt_running:_emit_status()
		return
	var unlimited := int(hunt_filter.rate)<=0
	if not unlimited:hunt_credit = minf(hunt_credit+delta*float(hunt_filter.rate),maxf(1.0,float(hunt_filter.rate)*HUNT_MAX_BACKLOG_SECONDS))
	var until := Time.get_ticks_usec()+HUNT_FRAME_BUDGET_USEC
	while hunt_running and (unlimited or hunt_credit>=1) and Time.get_ticks_usec()<until:
		if not unlimited:hunt_credit -= 1
		scan_once()
	hunt_elapsed = (Time.get_ticks_usec()-hunt_started_usec)/1000000.0
	if hunt_running:_emit_status()

## One GDScript scan step: the next roll of this run.
func scan_once() -> void:
	if not hunt_running:return
	# A direct step (tests, or after the helper) continues from the counters.
	if fast_hunt.running():fast_hunt.stop()
	_scan_index(hunt_rolls)

## Scans roll `index` of this run. `expected` is what the native helper
## reported for it: -1 when called by the GDScript scan, else the enemy slot of
## its hit, or -2 for an empty troop. The helper only searches; this replay
## decides, and a different outcome stops the hunt.
func _scan_index(index: int, expected := -1) -> void:
	hunt_rolls = index+1
	var troop := roll_at(index)
	if troop.is_empty():
		stop_hunt("原版遇敌数据或条件不完整，已停止；没有替换敌群。");return
	if expected==-2:
		stop_hunt(_fast_mismatch(index));return
	var i := first_match(troop)
	# The helper judged with the thresholds it was started with; a hit queued
	# since may have raised them, so a report the replay now rejects is not a
	# mismatch (the helper restarts with the new thresholds next frame).
	var raised := expected>=0 and not _fast_thresholds.is_empty() and threshold_key()!=_fast_thresholds
	if i<0:
		if expected>=0 and not raised:
			stop_hunt(_fast_mismatch(index));return
		if int(hunt_filter.limit)>0 and hunt_rolls>=int(hunt_filter.limit):stop_hunt("达到本轮遇敌上限，已暂停；可以再次开始。")
		return
	if expected>=0 and i!=expected and not raised:
		stop_hunt(_fast_mismatch(index));return
	var actor: Dictionary = troop.enemies[i]
	var quality: Dictionary = HuntRules.quality(actor,backend.encounter_catalog.data)
	if flow_showcase and flow_active():
		hunt_last_hit = {"actor":actor.duplicate(true),"index":i,"quality":quality,"troop":troop.duplicate(true)}
		# 展示模式: queue the hit and keep searching; flow_step takes it in turn.
		if TroopArt.can_render(troop.enemies):_showcase_enqueue(index,i,troop,quality)
		return
	_open_hit(troop,i,quality)

## A hit (or a survey pick) becomes a battle: the hunt stops, the battle opens
## and a find-pet cycle catches the pet (or 自动捕捉 does, if on).
func _open_hit(troop: Dictionary, i: int, quality: Dictionary) -> void:
	var filter := hunt_filter
	var actor: Dictionary = troop.enemies[i]
	hunt_last_hit = {"actor":actor.duplicate(true),"index":i,"quality":quality,"troop":troop.duplicate(true)}
	var found := "找到达标个体：%s Lv.%d，总成长档 %+d。" % [actor.name,actor.level,quality.total_offset]
	if not TroopArt.can_render(troop.enemies):
		stop_hunt(found+"\n敌群原版素材不可用，保留本次结果并停止，未进入战斗。");return
	var config: Dictionary = backend.session.start_wild_battle_config(troop)
	if config.is_empty():
		stop_hunt(found+"\n战斗校验未通过，已停止。");return
	stop_hunt(found)
	# The workflow resolves its capture fight without animation, like compact training.
	var workflow_capture := flow_phase=="hunt"
	if workflow_capture:
		compact_active = true
		_emit_status()
	backend.open_battle(config)
	var automatic: bool = workflow_capture or bool(filter.get("auto_capture",false))
	_emit_event({"kind":"hunt_hit","index":i,"actor":actor.duplicate(true),"quality":quality,"rolls":hunt_rolls,"automatic":automatic,"workflow":workflow_capture})
	if flow_phase=="hunt":matched(i,actor)
	elif bool(filter.get("auto_capture",false)):start_capture_battle(i)

## Roll `index` of this run, from its own seed (FastHunt.roll_seed).
func roll_at(index: int) -> Dictionary:
	hunt_rng.seed = FastHunt.roll_seed(hunt_run_seed,index)
	return hunt_catalog.roll(hunt_map,hunt_cell,hunt_rng)

## The first enemy slot of a rolled troop the hunt takes, or -1. Counts what it
## inspects (hunt_inspected, hunt_best, and during a find-pet cycle the
## predictions); the native helper implements the same rules.
func first_match(troop: Dictionary) -> int:
	var filter := hunt_filter
	for i in range(troop.enemies.size()):
		var actor: Dictionary = troop.enemies[i]
		if not actor.get("can_capture",false):continue
		if not int(actor.template_id) in filter.usable:continue
		if int(filter.template)>=0 and int(actor.template_id)!=int(filter.template):continue
		if filter.level_one and int(actor.level)!=1:continue
		hunt_inspected += 1
		var quality: Dictionary = HuntRules.quality(actor,backend.encounter_catalog.data)
		if quality.valid:hunt_best = maxi(hunt_best,int(quality.total_offset))
		if HuntRules.matches(actor,int(filter.template),bool(filter.level_one),int(filter.total),filter.offsets,backend.encounter_catalog.data):
			if _predicting() and surveying(int(actor.template_id)):
				# 摸底: a candidate, not a hit (the helper does the same).
				var projected: Dictionary = Progression.project_pet(actor,120)
				_note_best(projected)
				survey_add(hunt_run_seed,hunt_rolls-1,i,int(actor.template_id),_prediction(projected))
				continue
			if _predicting() and not accepts_prediction(actor):continue
			return i
	return -1

func _fast_mismatch(index: int) -> String:
	return "本机极速模式的结果与游戏复核不一致（第 %d 组），已停止，没有进入战斗。请关闭本机极速模式后再试，并报告这个问题。" % (index+1)

## 本机极速模式 for this frame: starts the helper when wanted and possible,
## and applies its reports. False when the GDScript scan should run instead:
## also while a 每秒遇敌 rate is set, since that asks for a throttled scan.
func _fast_process() -> bool:
	if not hunt_fast_wanted or not hunt_fast_note.is_empty() or int(hunt_filter.get("rate",0))>0:
		if fast_hunt.running():fast_hunt.stop()
		return false
	if not hunt_catalog is EncounterCatalog:return false
	# A better pet arrived (or a survey began or ended): the helper starts
	# again from the rolls already committed, with the new thresholds.
	if fast_hunt.running() and _predicting() and threshold_key()!=_fast_thresholds:
		_survey_merge(fast_hunt.peek().get("candidates",[]))
		fast_hunt.stop()
	if not fast_hunt.running():
		_fast_base = {"inspected":hunt_inspected,"best":hunt_best,"rejects":flow_predicted_rejects,"start":hunt_rolls}
		var area: Dictionary = hunt_catalog.area_at(hunt_map,hunt_cell)
		_fast_thresholds = threshold_key() if _predicting() else ""
		var rules := {}
		if _predicting():
			for id in survey.get("templates",[]):rules[int(id)] = raw_filter_for(int(id)).get("keep_rule",{})
		if not fast_hunt.launch(hunt_catalog.data,area,hunt_filter,_predicting(),filter_for,hunt_run_seed,hunt_rolls,fast_threads,rules):
			hunt_fast_note = "本机辅助程序无法启动，已改用普通筛选。"
			return false
		return true
	var report: Dictionary = fast_hunt.poll()
	if report.is_empty():return true
	_survey_merge(report.get("candidates",[]))
	if str(report.kind)=="exited":
		hunt_fast_note = "本机辅助程序意外结束，已改用普通筛选。"
		return false
	hunt_rolls = int(report.index)
	hunt_inspected = int(_fast_base.inspected)+int(report.inspected)
	hunt_best = maxi(int(_fast_base.best),int(report.best))
	flow_predicted_rejects = int(_fast_base.rejects)+int(report.predicted_rejects)
	if int(report.best_sum)>=0 and (flow_best_predicted.is_empty() or int(report.best_sum)>int(flow_best_predicted.sum) or (int(report.best_sum)==int(flow_best_predicted.sum) and int(report.best_attack)>int(flow_best_predicted.attack))):
		flow_best_predicted = {"sum":int(report.best_sum),"attack":int(report.best_attack)}
	match str(report.kind):
		"hit":_scan_index(int(report.index),int(report.slot))
		"stop":_scan_index(int(report.index),-2)
		"limit":stop_hunt("达到本轮遇敌上限，已暂停；可以再次开始。")
	return true

## Sets 线程数 (0 = auto) on this server; "" or the refusal reason. A running
## helper is stopped and the next frame starts it again from the rolls already
## committed (the helper reports them in order), so the change applies at once
## and no roll is skipped or repeated in the results.
func set_fast_threads(value: Variant) -> String:
	var error := ServerSettings.set_fast_hunt_threads(value)
	if not error.is_empty():return error
	fast_threads = int(value)
	if fast_hunt.running():fast_hunt.stop()
	_emit_status()
	return ""

## Threads the helper uses for a setting: all cores but one when automatic.
static func threads_used(setting: int) -> int:
	var cores := ServerSettings.cores()
	return setting if setting > 0 else (cores-1 if cores > 2 else 1)

# ---- find-pet workflow -----------------------------------------------------

func flow_active() -> bool:
	return flow_phase in ["hunt","reveal","capture","train","restart"]

## Whether hunt hits must also meet the Lv.120 stat conditions.
func _predicting() -> bool:
	return flow_phase=="hunt" or (flow_showcase and flow_active())

func elapsed_seconds() -> float:
	return maxf(0.0,(int(timer_clock.call())-timer_started_msec)/1000.0) if timer_running else timer_frozen_seconds

func start_timer() -> void:
	timer_started_msec = int(timer_clock.call());timer_frozen_seconds = 0.0;timer_running = true

func freeze_timer() -> void:
	timer_frozen_seconds = elapsed_seconds();timer_running = false

func collect_target_text() -> String:
	var stop_after := int(flow_target_filter.get("stop_after",1))
	return "不限" if stop_after<=0 else str(stop_after)

## The cycle's stat filter for a species as saved (最高 − x, unresolved).
func raw_filter_for(template_id: int) -> Dictionary:
	if flow_stat_filters.has(template_id):return flow_stat_filters[template_id]
	return AutomationSettings.stat_filter(flow_settings_overrides,template_id)

## The filter the hunt applies now: 最高 − x resolved against the species'
## best pets (species_maxima).
func filter_for(template_id: int) -> Dictionary:
	return StatFilter.resolve(raw_filter_for(template_id),species_maxima(template_id))

## Hunt-time gate: compute the exact Lv.120 stats from the wild pet's own seed and
## only let pets that will meet the conditions through to capture.
func accepts_prediction(actor: Dictionary) -> bool:
	var chosen := filter_for(int(actor.get("template_id",-1)))
	if not StatFilter.enabled(chosen):return true
	var projected: Dictionary = Progression.project_pet(actor,120)
	_note_best(projected)
	if StatFilter.evaluate(projected,chosen):return true
	flow_predicted_rejects += 1
	return false

func _note_best(projected: Dictionary) -> void:
	var total := int(projected.attack)+int(projected.defence)+int(projected.speed)
	if flow_best_predicted.is_empty() or total>int(flow_best_predicted.sum) or (total==int(flow_best_predicted.sum) and int(projected.attack)>int(flow_best_predicted.attack)):
		flow_best_predicted = {"sum":total,"attack":int(projected.attack)}

static func _prediction(projected: Dictionary) -> Dictionary:
	return {"attack":int(projected.attack),"defence":int(projected.defence),"speed":int(projected.speed),"max_hp":int(projected.max_hp)}

# ---- 最高 − x and 摸底 -------------------------------------------------------

## Clears the cached maxima when the player's pets changed.
func refresh_maxima() -> void:
	var key: String = backend.session.pet_signature()
	if key==_pets_key:return
	_pets_key = key
	_owned_maxima = {}
	_pets_profile = {}

var _pets_profile: Dictionary = {}

## The best Lv120 values among the player's own pets of a species (carried
## and warehouse, under Lv120 by exact projection), {} when there are none.
func owned_maxima(template_id: int) -> Dictionary:
	if not _owned_maxima.has(template_id):
		if _pets_profile.is_empty():_pets_profile = backend.session.snapshot()
		_owned_maxima[template_id] = StatFilter.maxima(KeepRule.species_pets(_pets_profile,template_id).map(KeepRule.stats_of))
	return _owned_maxima[template_id]

## owned_maxima raised by the pets the cycle is about to catch: survey picks
## and, with 后台搜宠, the queued hits and the one being caught. A hit is only
## worth queueing if it could beat what is already waiting.
func species_maxima(template_id: int) -> Dictionary:
	var pending: Array = []
	for entry in _pending_picks()+_queued_hits():
		if int(entry.actor.get("template_id",-1))==template_id:pending.append(entry.prediction)
	return StatFilter.maxima(pending,owned_maxima(template_id))

func _queued_hits() -> Array:
	var result: Array = showcase_queue.filter(func(entry):return not bool(entry.get("survey",false)))
	if not showcase_current.is_empty() and not bool(showcase_current.get("survey",false)) and flow_phase=="capture":result.append(showcase_current)
	return result

func _pending_picks() -> Array:
	var result: Array = survey_picks.duplicate()
	for entry in showcase_queue:
		if bool(entry.get("survey",false)):result.append(entry)
	if bool(showcase_current.get("survey",false)) and flow_phase=="capture":result.append(showcase_current)
	return result

## The species this hunt may take: its usable ones, or the one chosen.
func _hunt_templates() -> Array:
	var result: Array = []
	for id in hunt_filter.get("usable",[]):
		if int(hunt_filter.get("template",-1))<0 or int(id)==int(hunt_filter.template):result.append(int(id))
	return result

## The resolved thresholds of every species the hunt may take, and which are
## being surveyed: when this changes the native helper restarts.
func threshold_key() -> String:
	var parts: Array = []
	for id in _hunt_templates():
		var chosen := filter_for(id)
		parts.append([id,surveying(id),chosen.get("mode",""),chosen.get("conditions",{}).values().map(func(c):return [c.get("enabled",false),c.get("value",null)])])
	return JSON.stringify(parts)

func surveying(template_id: int) -> bool:
	return not survey.is_empty() and survey.templates.has(template_id)

## Species of this hunt whose enabled 最高 − x conditions have nothing to
## count from (no pet of theirs, and no survey pick on the way).
func _survey_wanted() -> Array:
	var result: Array = []
	for id in _hunt_templates():
		if StatFilter.needs_survey(raw_filter_for(id),species_maxima(id)):result.append(id)
	return result

func survey_remaining() -> float:
	if survey.is_empty():return 0.0
	return maxf(0.0,float(survey_seconds)-(int(survey_clock.call())-int(survey.started))/1000.0)

func _template_name(template_id: int) -> String:
	return str(backend.encounter_catalog.data.get("templates",{}).get(str(template_id),{}).get("name","#%d" % template_id))

## Starts a survey when a species needs one; ends it when its time is up.
func _survey_process() -> void:
	if survey.is_empty():
		var wanted := _survey_wanted()
		if wanted.is_empty():return
		survey = {"templates":wanted,"started":int(survey_clock.call()),"candidates":{},"runs":[]}
		var names: Array = wanted.map(_template_name)
		_showcase_line("survey","摸底：还没有%s，先不设门槛找%s，再按保留规则挑最好的抓。" % ["、".join(names),_duration(survey_seconds)])
		_emit_status()
	elif survey_remaining()<=0.0:
		_finish_survey()

static func _duration(seconds: float) -> String:
	var s := int(seconds)
	return "%d分钟" % (s/60) if s>=60 and s%60==0 else ("%d分%02d秒" % [s/60,s%60] if s>=60 else "%d秒" % s)

## One survey candidate (from the GDScript scan or the helper's pool).
func survey_add(run_seed: int, index: int, slot: int, template_id: int, prediction: Dictionary) -> void:
	if not surveying(template_id):return
	var key := "%d:%d:%d" % [run_seed,index,slot]
	if survey.candidates.has(key):return
	if not survey.runs.has(run_seed):survey.runs.append(run_seed)
	# Ties resolve to the earlier roll, as the helper's pool (and 保留规则's
	# older pet id) does.
	var serial: int = (survey.runs.find(run_seed) << 40) | (index*16+slot)
	survey.candidates[key] = {"run_seed":run_seed,"index":index,"slot":slot,"template_id":template_id,"prediction":prediction.duplicate(),"serial":serial}
	if survey.candidates.size()>512:
		var kept := {}
		for pick in survey_choose(survey.candidates.values()):kept["%d:%d:%d" % [int(pick.run_seed),int(pick.index),int(pick.slot)]] = true
		for k in survey.candidates.keys():
			if not kept.has(k):survey.candidates.erase(k)

func _survey_merge(candidates: Array) -> void:
	for c in candidates:survey_add(hunt_run_seed,int(c.index),int(c.slot),int(c.template_id),c.prediction)

## What each species' 保留规则 would keep of these candidates (the functional
## core of the survey): the top tiers of 三围合, the best per tier by the
## rule's order, and the single-stat champions. Best first.
func survey_choose(candidates: Array) -> Array:
	var by_template := {}
	for c in candidates:
		if not by_template.has(int(c.template_id)):by_template[int(c.template_id)] = []
		by_template[int(c.template_id)].append(c)
	var result: Array = []
	for id in by_template:
		var rule: Dictionary = raw_filter_for(int(id)).get("keep_rule",{})
		result.append_array(choose_by_rule(by_template[id],rule))
	return result

## choose_by_rule on plain candidates {serial, prediction, ...}, best first.
static func choose_by_rule(candidates: Array, rule: Dictionary) -> Array:
	var pets: Array = []
	var by_id := {}
	for c in candidates:
		var p: Dictionary = c.prediction
		var id := "pet-%d" % int(c.serial)
		by_id[id] = c
		pets.append({"pet_id":id,"level":120,"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)})
	var verdict: Dictionary = KeepRule.evaluate(pets,rule)
	var kept: Array = pets.filter(func(pet):return not verdict.reasons[str(pet.pet_id)].is_empty())
	kept = StatFilter.ranked(kept,["sum"]+Array(rule.get("order",["attack","speed","max_hp"])))
	return kept.map(func(pet):
		var c: Dictionary = by_id[str(pet.pet_id)].duplicate()
		c.reasons = verdict.reasons[str(pet.pet_id)]
		return c)

## Time is up: take the helper's last pool, replay every candidate from its
## own seed (a mismatch is left out), choose by the keep rule and queue the
## picks for capture. Picks count toward 最高 until caught, so the hunt goes
## on with thresholds at once.
func _finish_survey() -> void:
	if fast_hunt.running():
		_survey_merge(fast_hunt.peek().get("candidates",[]))
		fast_hunt.stop()
	var finished := survey
	survey = {}
	var verified: Array = []
	var mismatched := 0
	for c in finished.candidates.values():
		var entry := _replay_candidate(c)
		if entry.is_empty():mismatched += 1
		else:verified.append(entry)
	var picks := survey_choose(verified)
	var names: Array = finished.templates.map(_template_name)
	var text := "摸底结束（%s）：候选 %d 只%s，按保留规则选中 %d 只" % ["、".join(names),verified.size(),"（复核不一致 %d 只，已略过）" % mismatched if mismatched>0 else "",picks.size()]
	var shown: Array = picks.slice(0,3).map(func(p):return "第%d组 %s（%s）" % [int(p.index)+1,_stat_text(p.prediction),"、".join(p.reasons)])
	if not shown.is_empty():text += "：" + "；".join(shown) + ("……" if picks.size()>3 else "")
	if picks.is_empty():text += "，重新摸底。"
	survey_last = {"candidates":verified.size(),"picked":picks.size(),"text":text}
	_showcase_line("survey",text)
	print("[找宠流程] "+text)
	for p in picks:
		p.survey = true
		if flow_showcase:_showcase_add(p)
		else:survey_picks.append(p)
	_emit_status()

## A candidate replayed from its own seed: the queue entry {index, slot,
## run_seed, actor, troop, quality, prediction}, or {} when it differs.
func _replay_candidate(c: Dictionary) -> Dictionary:
	if hunt_catalog==null:return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = FastHunt.roll_seed(int(c.run_seed),int(c.index))
	var troop: Dictionary = hunt_catalog.roll(hunt_map,hunt_cell,rng)
	var enemies: Array = troop.get("enemies",[])
	if int(c.slot)<0 or int(c.slot)>=enemies.size():return {}
	var actor: Dictionary = enemies[int(c.slot)]
	if int(actor.get("template_id",-1))!=int(c.template_id) or not actor.get("can_capture",false):return {}
	if not HuntRules.matches(actor,int(hunt_filter.template),bool(hunt_filter.level_one),int(hunt_filter.total),hunt_filter.offsets,backend.encounter_catalog.data):return {}
	var prediction := _prediction(Progression.project_pet(actor,120))
	if prediction!=c.prediction or not TroopArt.can_render(enemies):return {}
	return {"index":int(c.index),"slot":int(c.slot),"run_seed":int(c.run_seed),"serial":int(c.serial),"template_id":int(c.template_id),"actor":actor.duplicate(true),
		"troop":troop.duplicate(true),"quality":HuntRules.quality(actor,backend.encounter_catalog.data),"prediction":prediction}

## 后台搜宠 off: the next survey pick is caught like a hit (replayed again
## from its seed first; a different troop is skipped).
func _take_survey_pick() -> void:
	var entry: Dictionary = survey_picks.pop_front()
	var replayed := _replay_candidate(entry)
	if replayed.is_empty() or JSON.stringify(replayed.troop)!=JSON.stringify(entry.troop):
		_showcase_line("skipped","摸底选中的第 %d 组复核不一致，已略过。" % (int(entry.index)+1))
		return
	_open_hit(replayed.troop,int(replayed.slot),replayed.quality)
	if flow_phase=="capture":flow_target_survey = true

func start_cycle(continuing: bool) -> bool:
	if flow_active():return false
	if backend.battle.snapshot().get("active",false) or backend.battle_open:
		flow_reason = "请先结束战斗或移动，再开始一轮找宠。";return false
	if backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
		flow_reason = "宠物栏已满，请自行存放伙伴后再开始。";return false
	if not continuing or flow_run_id.is_empty():
		_flow_run_serial += 1
		flow_run_id = "%d-%d" % [int(Time.get_unix_time_from_system()),_flow_run_serial]
	if not continuing:
		flow_stored_count = 0;flow_pruned_count = 0;flow_kept_count = 0;flow_collected_count = 0;flow_predicted_rejects = 0;flow_best_predicted = {};flow_last_result = "";flow_last_stored_id = "";flow_run_reject_ids = [];flow_released_count = 0;flow_held_count = 0
		flow_skip_kind = "";flow_skip_streak = 0;flow_skipped_count = 0;flow_skip_note = ""
		survey = {};survey_picks = [];survey_last = {};flow_target_survey = false;_pets_key = ""
		start_timer()
	flow_map = position_map
	flow_cell = position_cell
	flow_known_ids.clear();flow_pet_id = "";flow_matched_actor = {};flow_matched_index = -1;flow_capture_battle_id = "";flow_reason = ""
	for pet in backend.session.snapshot().pets:flow_known_ids[str(pet.pet_id)] = true
	flow_phase = "hunt"
	if not continuing:
		flow_showcase = bool(flow_hunt_request.get("showcase",false))
		showcase_queue = [];showcase_current = {};showcase_log = []
	_emit_event({"kind":"flow_hunt"})
	if not start_hunt(flow_hunt_request):
		stop_cycle(hunt_status);return false
	_emit_status()
	return true

func matched(index: int, actor: Dictionary) -> void:
	if flow_phase!="hunt":return
	refresh_maxima()
	flow_target_survey = false
	flow_target_filter = filter_for(int(actor.get("template_id",-1))).duplicate(true)
	flow_matched_index = index
	flow_matched_actor = actor.duplicate(true)
	flow_capture_battle_id = str(backend.battle.snapshot().get("battle_id",""))
	flow_phase = "capture"
	start_capture_battle(index,true)
	if not running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。")

## 停止 from the player: a pet being caught or trained is finished first (the
## search stops and the queue is let go now); the cycle then stops where it
## would start the next one. Asked again while waiting, it stops at once.
func request_stop_cycle(message: String) -> void:
	if not flow_active() or flow_phase not in ["capture","train"] or not flow_stop_pending.is_empty():
		stop_cycle(message);return
	flow_stop_pending = message
	if not showcase_queue.is_empty():
		_showcase_line("dropped","停止：排队的 %d 只已放弃，本只练完后停止" % showcase_queue.size())
		showcase_queue = []
	else:_showcase_line("dropped","停止：本只练完后停止（再按一次立即停止）")
	if hunt_running:
		_stopping_cycle = true
		stop_hunt(message)
		_stopping_cycle = false
	_emit_status()

func stop_cycle(message: String = "已手动停止") -> void:
	flow_stop_pending = ""
	if message.is_empty():message = "找宠流程已停止（没有写明原因）。"
	if flow_active():_record_stop("flow","停止",message,_involved_pet())
	_stopping_cycle = true
	if not showcase_queue.is_empty():
		_showcase_line("dropped","排队的 %d 只已放弃：%s" % [showcase_queue.size(),message])
		message += "（排队的 %d 只已放弃）" % showcase_queue.size()
	if not survey_picks.is_empty():_showcase_line("dropped","摸底选中的 %d 只未捕获：%s" % [survey_picks.size(),message])
	showcase_queue = []
	survey = {}
	survey_picks = []
	_showcase_restore()
	freeze_timer()
	flow_phase = "paused"
	flow_reason = message
	if hunt_running:stop_hunt(message)
	if running:stop(message)
	_stopping_cycle = false
	_emit_status()
	_emit_event({"kind":"flow_paused","reason":message})

func flow_step() -> void:
	if not flow_active():return
	if position_map!=flow_map or position_cell!=flow_cell:
		stop_cycle("位置发生变化；请在当前位置重新开始。");return
	if flow_showcase:
		_showcase_step()
		return
	if not flow_stop_pending.is_empty() and flow_phase in ["restart","hunt"]:
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	if flow_phase=="restart":
		flow_phase = "idle"
		if not start_cycle(true):stop_cycle(flow_reason)
		return
	if flow_phase=="hunt":
		if not hunt_running:stop_cycle(hunt_status)
		return
	if running:return
	if flow_phase=="capture":
		# Only the normal single-battle completion continues with this pet; a
		# failed capture skips it (_capture_failed), a manual Stop is final.
		if _capture_failed():return
		var fresh: Array = []
		var pets: Array = backend.session.snapshot().pets
		for i in range(pets.size()):
			if not flow_known_ids.has(str(pets[i].get("pet_id",""))):fresh.append(i)
		if fresh.size()!=1 or not same_capture(pets[fresh[0]],flow_matched_actor):
			stop_cycle("无法唯一确认新捕获伙伴，请手动检查宠物栏。");return
		flow_pet_id = str(pets[fresh[0]].pet_id)
		_capture_succeeded()
		if not backend.session.select_pet(int(fresh[0])):stop_cycle("新伙伴无法出战。");return
		backend.save()
		backend.publish()
		flow_phase = "train"
		# Growth is seeded per pet and level, so instant levelling equals battle training.
		backend.session.last_error = ""
		if not backend.session.level_pet_to(flow_pet_id,120):stop_cycle("无法升至120级："+str(backend.session.last_error));return
		backend.save()
		backend.publish()
		var leveled: Dictionary = {}
		for pet in backend.session.snapshot().pets:
			if str(pet.get("pet_id",""))==flow_pet_id:leveled = pet
		complete_trained_pet(leveled)
		return
	if flow_phase=="train":
		if stop_reason!="目标宠物已达到等级目标":stop_cycle(stop_reason);return
		var found: Dictionary = {}
		for pet in backend.session.snapshot().pets:
			if str(pet.get("pet_id",""))==flow_pet_id:found = pet
		if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
		complete_trained_pet(found)

func _store_hunt_pet(pet_id: String, prunable: bool, qualified: bool = false) -> bool:
	var index := -1
	var pets: Array = backend.session.snapshot().pets
	for i in range(pets.size()):
		if str(pets[i].get("pet_id",""))==pet_id:index = i;break
	backend.session.last_error = ""
	return index>=0 and backend.session.store_pet(index,prunable,qualified)

func complete_trained_pet(found: Dictionary) -> void:
	if flow_phase!="train":return
	# Use settled actual attributes, never the forecast or a different pet's ID.
	if str(found.get("pet_id",""))!=flow_pet_id or int(found.get("level",0))<120:
		stop_cycle("目标宠物未达到120级，请手动检查。");return
	var filtered := StatFilter.enabled(flow_target_filter)
	# A survey pick is what the survey found best: it counts as found.
	var passed := flow_target_survey or StatFilter.evaluate(found,flow_target_filter)
	flow_last_result = "%s · %s" % [flow_pet_id,"摸底选中" if flow_target_survey else StatFilter.describe(found,flow_target_filter)] if filtered else "新伙伴已达到120级"
	if filtered and not passed:
		if not _store_hunt_pet(flow_pet_id,true):
			stop_cycle("未达标但无法存仓："+str(backend.session.last_error));return
		flow_stored_count += 1
		flow_run_reject_ids.append(flow_pet_id)
		flow_last_stored_id = flow_pet_id
		flow_last_stored_total = int(found.attack)+int(found.defence)+int(found.speed)
		flow_last_result = "未达标已存仓 · "+flow_last_result
		flow_pruned_count += backend.session.prune_hunt_pets(int(found.get("template_id",-1)),StatFilter.keep_counts(flow_target_filter),flow_run_reject_ids)
		if _tidy_species(found).has(flow_pet_id):flow_last_result = "未达标已存仓，按保留规则放生 · "+flow_last_result.trim_prefix("未达标已存仓 · ")
		backend.save()
		backend.publish()
		# A separate step leaves cancellation/reload a boundary before restarting.
		flow_phase = "restart"
		flow_reason = flow_last_result
		_emit_status()
		_emit_event({"kind":"flow_stored","result":flow_last_result})
		return
	var stop_after := int(flow_target_filter.get("stop_after",1))
	if filtered and stop_after!=1:
		# Keep the qualifier in the warehouse (never pruned as a reject) and continue.
		if not _store_hunt_pet(flow_pet_id,false,true):
			stop_cycle("达标但无法存仓："+str(backend.session.last_error));return
		flow_kept_count += 1
		flow_collected_count += 1
		var released := _tidy_species(found)
		backend.save()
		backend.publish()
		if released.has(flow_pet_id):flow_last_result = "达标但不在保留规则内，已放生 · "+flow_last_result
		else:flow_last_result = "达标已存仓 · "+flow_last_result
		if stop_after>0 and flow_collected_count>=stop_after:
			freeze_timer()
			_record_stop("flow","完成","收集完成：本轮找到%d只达标宠物" % flow_collected_count,_involved_pet())
			flow_phase = "compare"
			flow_reason = "收集完成：本轮找到%d只达标宠物 · %s" % [flow_collected_count,flow_last_result]
			_emit_status()
			_emit_event({"kind":"flow_compare","pet_id":flow_pet_id,"reason":flow_reason})
			return
		flow_phase = "restart"
		flow_reason = flow_last_result
		_emit_status()
		_emit_event({"kind":"flow_stored","result":flow_last_result})
		return
	freeze_timer()
	_record_stop("flow","完成","已达标，停下来比较" if filtered else "新伙伴已达到120级，停下来比较",_involved_pet())
	flow_phase = "compare"
	flow_reason = ("已达标 · "+flow_last_result) if filtered else "新伙伴已达到120级，请对比后自行决定去留。"
	_emit_status()
	_emit_event({"kind":"flow_compare","pet_id":flow_pet_id,"reason":flow_reason})

## 保留规则 with 找宠时自动整理 on: after a stored pet, the whole species
## (carried and warehouse) is tidied; favourites, the active pet, the mount and
## the capture helper stay. Returns the released ids.
func _tidy_species(found: Dictionary) -> Array:
	var rule: Dictionary = flow_target_filter.get("keep_rule",{})
	if not bool(rule.get("auto",false)):return []
	var template := int(found.get("template_id",-1))
	var released: Array = backend.session.apply_keep_rule(template,rule,capture_helpers())
	flow_released_count += released.size()
	flow_held_count = KeepRule.species_pets(backend.session.snapshot(),template).size()
	return released

## Carried pets the capture step may use (the chosen helper, or with automatic
## choice every one at or under the level cap): the tidy never releases them.
func capture_helpers() -> Dictionary:
	var capture: Dictionary = AutomationSettings.effective(backend.session.automation_settings()).get("capture",{})
	return KeepRule.capture_helpers(backend.session.snapshot(),capture)

static func same_capture(pet: Dictionary, actor: Dictionary) -> bool:
	for key in ["template_id","species","level","growth_weights","growth_seed","growth_rank","base_stats"]:
		if actor.has(key) and pet.get(key)!=actor[key]:return false
	return true

# ---- stops and skips (停止记录) --------------------------------------------

## One 停止记录 entry and a line on the server's output. scope: hunt (a scan on
## its own) or flow (the find-pet cycle); outcome: 停止, 暂停, 已跳过, 已重试,
## 完成 or 找到 (a scan on its own found its pet). Counts are the run's so far.
func _record_stop(scope: String, outcome: String, reason: String, pet: Dictionary = {}) -> void:
	var entry := {"time":int(Time.get_unix_time_from_system()),"scope":scope,"outcome":outcome,"reason":reason,
		"phase":flow_phase if scope=="flow" else "hunt","run":flow_run_id if scope=="flow" else "",
		"rolls":hunt_rolls,"collected":flow_collected_count,"stored":flow_stored_count,"skipped":flow_skipped_count,"released":flow_released_count,
		"map_id":position_map,"map_name":backend.map_name(position_map) if position_map>=0 else "","cell":[position_cell.x,position_cell.y],"pet_id":str(pet.get("pet_id","")),"name":str(pet.get("name",""))}
	stop_events.append(entry)
	var who := ""
	if not str(entry.name).is_empty():who = " · %s%s" % [entry.name," "+str(entry.pet_id) if not str(entry.pet_id).is_empty() else ""]
	print("[%s] %s：%s%s · 已遇敌 %d 组 · 达标 %d · 存仓 %d · 跳过 %d" % ["找宠流程" if scope=="flow" else "自动抓极品",outcome,reason.replace("\n"," "),who,hunt_rolls,flow_collected_count,flow_stored_count,flow_skipped_count])

func take_stop_events() -> Array:
	var result := stop_events
	stop_events = []
	return result

## The server is shutting down (a restart or quit) while a hunt or cycle runs.
func record_shutdown() -> void:
	var reason := "服务器关闭（重启或退出），自动抓极品中断；重新打开后需要再次开始。"
	if flow_active():_record_stop("flow","停止",reason,_involved_pet())
	elif hunt_running:_record_stop("hunt","停止",reason)

## The pet the cycle is working on, for the log: the captured pet once there
## is one, else the matched or revealed wild pet (name only).
func _involved_pet() -> Dictionary:
	if not flow_pet_id.is_empty():
		var pet := _flow_pet()
		return {"pet_id":flow_pet_id,"name":str(pet.get("name",flow_matched_actor.get("name","")))}
	if not flow_matched_actor.is_empty():return {"name":str(flow_matched_actor.get("name",""))}
	if not showcase_current.is_empty():return {"name":str(showcase_current.get("actor",{}).get("name",""))}
	return {}

static func skippable_battle_stop(reason: String) -> bool:
	return reason in SKIPPABLE_BATTLE_STOPS or reason.ends_with("体力达到停机线")

## After the capture battle: true (and the hit skipped or the cycle stopped)
## when it ended without the matched pet. A manual stop, a full party or
## anything else that needs the player stops; the target going down, a lost or
## overlong battle, or a closed battle without the pet skip it.
func _capture_failed() -> bool:
	if stop_reason!="本场自动战斗已完成":
		if skippable_battle_stop(stop_reason):_skip_hit("捕捉失败",stop_reason)
		else:stop_cycle(stop_reason)
		return true
	var battle: Dictionary = backend.battle.snapshot()
	if battle.get("active",false) or str(battle.get("battle_id",""))!=flow_capture_battle_id:
		# Another battle is open (say, from another device): leave it to the player.
		if backend.battle_open:stop_cycle("捕捉战斗状态已改变。")
		else:_skip_hit("捕捉失败","捕捉战斗状态已改变。")
		return true
	var enemies: Array = battle.get("enemies",[])
	if flow_matched_index<0 or flow_matched_index>=enemies.size() or not enemies[flow_matched_index].get("captured",false):
		_skip_hit("捕捉失败","目标未捕获；未改抓其他敌人。")
		return true
	return false

func _capture_succeeded() -> void:
	flow_skip_kind = ""
	flow_skip_streak = 0

## Steps past a hit the cycle cannot finish: logs 已跳过, ends a capture battle
## still open (no rewards), and goes back to searching (展示模式: the next
## queued hit). The same kind SKIP_LIMIT times in a row stops the cycle.
func _skip_hit(kind: String, reason: String) -> void:
	if kind==flow_skip_kind:flow_skip_streak += 1
	else:
		flow_skip_kind = kind
		flow_skip_streak = 1
	if flow_skip_streak>=SKIP_LIMIT:
		stop_cycle("连续%d次%s，已停止：%s" % [SKIP_LIMIT,kind,reason]);return
	var pet := _involved_pet()
	if running:
		release_clone_override()
		running = false
	compact_active = false
	backend.set_capture_assist(false)
	backend.abandon_battle()
	flow_skipped_count += 1
	flow_skip_note = "%s · %s" % [kind,reason]
	_record_stop("flow","已跳过",reason,pet)
	if flow_showcase:
		_showcase_restore()
		_showcase_line("skipped","已跳过：%s" % flow_skip_note)
	else:flow_reason = flow_skip_note
	flow_phase = "restart"
	_emit_status()
	_emit_event({"kind":"flow_skipped","reason":reason,"note":"已跳过一只 · "+flow_skip_note})

# ---- 后台搜宠 (showcase) ---------------------------------------------------
# The cycle keeps searching with the native helper while the player watches
# the normal game: a found pet's capture battle as any capture is shown, then
# 自动练级 to Lv.120 with the player's own 经验倍率 and 战斗速度, every battle
# played in full. Hits found meanwhile wait in showcase_queue. The name the
# player sees is AutomationSettings.SHOWCASE_NAME.

## Queued hits best first, as the keep rule ranks pets: 三围合, then the
## species' 保留规则 order, then the earlier roll.
func _showcase_better(a: Dictionary, b: Dictionary) -> bool:
	var rule: Dictionary = filter_for(int(a.actor.get("template_id",-1))).get("keep_rule",{})
	for key in StatFilter.rank_order(["sum"]+Array(rule.get("order",["attack","speed","max_hp"]))):
		var va := StatFilter.rank_value(a.prediction,key)
		var vb := StatFilter.rank_value(b.prediction,key)
		if va!=vb:return va>vb
	return int(a.index)<int(b.index)

func queue_limit() -> int:
	return clampi(int(flow_hunt_request.get("queue",SHOWCASE_QUEUE_MAX)),1,50)

## A hit found while the player watches (or idle). When the queue is over
## its limit the lowest ranked hit, possibly this one, is dropped and written
## to 放生记录 as 未捕获·排队已满.
func _showcase_enqueue(index: int, slot: int, troop: Dictionary, quality: Dictionary) -> void:
	var actor: Dictionary = troop.enemies[slot]
	var projected: Dictionary = Progression.project_pet(actor,120)
	_showcase_add({"index":index,"slot":slot,"run_seed":hunt_run_seed,"actor":actor.duplicate(true),"troop":troop.duplicate(true),"quality":quality.duplicate(true),
		"prediction":_prediction(projected)})

## Queues an entry (a hit, or a survey pick marked survey) best first.
func _showcase_add(entry: Dictionary) -> void:
	showcase_queue.append(entry)
	showcase_queue.sort_custom(_showcase_better)
	_prune_below_threshold()
	while showcase_queue.size()>queue_limit():_drop_queued(showcase_queue.pop_back())
	_emit_status()

## Queued hits a better one (queued or owned) has put below the thresholds are
## let go at once, in one line, instead of each when its turn comes.
func _prune_below_threshold() -> void:
	var dropped := 0
	var kept: Array = []
	var described := ""
	for entry in showcase_queue:
		var id := int(entry.actor.get("template_id",-1))
		var chosen := filter_for(id)
		if bool(entry.get("survey",false)) or not StatFilter.enabled(chosen) or StatFilter.evaluate(entry.prediction,chosen):
			kept.append(entry);continue
		dropped += 1
		described = "%s：%s" % [_template_name(id),StatFilter.describe_thresholds(raw_filter_for(id),species_maxima(id))]
	if dropped==0:return
	showcase_queue = kept
	_showcase_line("dropped","门槛已提高（%s），排队中 %d 只不再够格，已放弃" % [described,dropped])

func _drop_queued(entry: Dictionary) -> void:
	var limit := queue_limit()
	var p: Dictionary = entry.prediction
	var pet: Dictionary = entry.actor.duplicate(true)
	pet.pet_id = "第%d组" % (int(entry.index)+1)
	var beaters: Array = []
	# The hits just above it in the queue.
	for i in range(maxi(0,showcase_queue.size()-3),showcase_queue.size()):
		var above: Dictionary = showcase_queue[i]
		beaters.push_front(ReleaseLog.beater({"pet_id":"第%d组" % (int(above.index)+1),"name":str(above.actor.get("name",""))},above.prediction))
	var reason := "排队已满（上限%d），排在第%d" % [limit,limit+1]
	var logged := ReleaseLog.entry(pet,"未捕获","排队已满",reason,beaters,p)
	logged.uncaught = true
	logged.roll = int(entry.index)+1
	backend.session.release_events.append(logged)
	_showcase_line("dropped","排队已满：放弃第%d组 %s（预测三围合%d），%s" % [int(entry.index)+1,str(entry.actor.get("name","")),int(p.attack)+int(p.defence)+int(p.speed),reason])

func _queue_summary() -> Array:
	var result: Array = []
	for entry in showcase_queue:
		var p: Dictionary = entry.prediction
		result.append({"roll":int(entry.index)+1,"name":str(entry.actor.get("name","")),"sum":int(p.attack)+int(p.defence)+int(p.speed),"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)})
	return result

## One line of the scrolling info block every watching device shows at the top
## left: found, captured, Lv.120, 留下 / 放生, skips and queue drops.
func _showcase_line(kind: String, text: String) -> void:
	_showcase_log_serial += 1
	showcase_log.append({"id":_showcase_log_serial,"kind":kind,"text":text})
	while showcase_log.size()>SHOWCASE_LOG_MAX:showcase_log.pop_front()
	_emit_status()

func _flow_pet() -> Dictionary:
	for pet in backend.session.snapshot().pets:
		if str(pet.get("pet_id",""))==flow_pet_id:return pet
	return {}

static func _stat_text(stats: Dictionary) -> String:
	return "攻%d 防%d 敏%d 血%d · 三围合%d" % [int(stats.attack),int(stats.defence),int(stats.speed),int(stats.max_hp),int(stats.attack)+int(stats.defence)+int(stats.speed)]

## One find-pet step while searching in the background.
func _showcase_step() -> void:
	if not flow_stop_pending.is_empty() and flow_phase in ["restart","hunt"]:
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	match flow_phase:
		"hunt":
			if not showcase_queue.is_empty():_showcase_capture()
			elif not hunt_running:stop_cycle(hunt_status if not hunt_status.is_empty() else "筛选已停止。")
		"capture":
			if not running:_showcase_captured()
		"train":
			if running:return
			if stop_reason=="目标宠物已达到等级目标":_showcase_finished();return
			# A lost or overlong training battle: fight on (the pet keeps its
			# levels); the same failure SKIP_LIMIT times in a row stops the cycle.
			if skippable_battle_stop(stop_reason):
				if stop_reason==flow_skip_kind:flow_skip_streak += 1
				else:
					flow_skip_kind = stop_reason
					flow_skip_streak = 1
				if flow_skip_streak>=SKIP_LIMIT:stop_cycle("连续%d次%s，已停止。" % [SKIP_LIMIT,stop_reason]);return
				_record_stop("flow","已重试",stop_reason,_involved_pet())
				_showcase_line("retry","练级战斗没打完（%s），继续练级。" % stop_reason)
				backend.abandon_battle()
				_showcase_train()
				return
			stop_cycle(stop_reason)
		"restart":_showcase_resume()

## Takes the best queued hit, replays its roll from its own seed, checks it is
## the same troop, and opens its capture battle, presented like any capture.
func _showcase_capture() -> void:
	refresh_maxima()
	showcase_current = showcase_queue.pop_front()
	var entry := showcase_current
	var actor: Dictionary = entry.actor
	flow_target_survey = bool(entry.get("survey",false))
	flow_target_filter = filter_for(int(actor.get("template_id",-1))).duplicate(true)
	var p: Dictionary = entry.prediction
	# The thresholds may have risen since this hit was queued (a better pet
	# arrived): one no longer good enough is let go. Survey picks are caught.
	if not flow_target_survey and StatFilter.enabled(flow_target_filter) and not StatFilter.evaluate(p,flow_target_filter):
		_showcase_line("dropped","门槛已提高（%s），放弃第%d组 %s（预测%s）" % [StatFilter.describe_thresholds(raw_filter_for(int(actor.get("template_id",-1))),species_maxima(int(actor.get("template_id",-1)))),int(entry.index)+1,str(actor.get("name","")),_stat_text(p)])
		showcase_current = {}
		return
	var full := int(entry.quality.get("total_offset",0))==8
	var rarity: Array = Rarity.describe(int(actor.get("template_id",-1)),p,full)
	_showcase_line("found","%s%s%s · 预测120级 %s%s · 排队%d" % ["摸底选中" if flow_target_survey else "找到","满档" if full else "",str(actor.get("name","")),_stat_text(p),"（"+str(rarity[0]).get_slice("：",1)+"）" if full and rarity.size()>0 and str(rarity[0]).contains("1/") else "",showcase_queue.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = FastHunt.roll_seed(int(entry.run_seed),int(entry.index))
	var troop: Dictionary = hunt_catalog.roll(flow_map,flow_cell,rng) if hunt_catalog!=null else {}
	if troop.is_empty() or JSON.stringify(troop)!=JSON.stringify(entry.troop):
		_skip_hit("复核不一致","排队的第 %d 组复核不一致，没有进入战斗。" % (int(entry.index)+1));return
	if backend.session.snapshot().pets.size()>=GameSession.PET_CAPACITY:
		stop_cycle("宠物栏已满，请自行存放伙伴后再开始。");return
	var config: Dictionary = backend.session.start_wild_battle_config(troop)
	if config.is_empty():stop_cycle("战斗校验未通过，已停止。");return
	flow_known_ids.clear()
	for pet in backend.session.snapshot().pets:flow_known_ids[str(pet.pet_id)] = true
	flow_matched_index = int(entry.slot)
	flow_matched_actor = actor.duplicate(true)
	compact_active = false
	showcase_show_battle = true
	backend.open_battle(config)
	flow_capture_battle_id = str(backend.battle.snapshot().get("battle_id",""))
	flow_phase = "capture"
	start_capture_battle(flow_matched_index,true)
	if not running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。");return
	_emit_status()
	# Devices clear the stage for the battle (the hunt window folds away).
	_emit_event({"kind":"flow_reveal"})

## After the capture battle: the same checks as the full-speed cycle, then
## 自动练级 to Lv.120.
func _showcase_captured() -> void:
	showcase_show_battle = false
	if _capture_failed():return
	var fresh: Array = []
	var pets: Array = backend.session.snapshot().pets
	for i in range(pets.size()):
		if not flow_known_ids.has(str(pets[i].get("pet_id",""))):fresh.append(i)
	if fresh.size()!=1 or not same_capture(pets[fresh[0]],flow_matched_actor):
		stop_cycle("无法唯一确认新捕获伙伴，请手动检查宠物栏。");return
	flow_pet_id = str(pets[fresh[0]].pet_id)
	_capture_succeeded()
	if not backend.session.select_pet(int(fresh[0])):stop_cycle("新伙伴无法出战。");return
	backend.save()
	backend.publish()
	_showcase_line("captured","捕获成功：%s %s，开始练到120级。" % [str(pets[fresh[0]].get("name","")),flow_pet_id])
	flow_phase = "train"
	_showcase_train()

## 自动练级 for the caught pet: the player's own 经验倍率 (training.xp), every
## battle shown at this device's 战斗速度, the pet active and the 五人镜像队 made
## of the player's other best pets. The runner stops only between battles,
## once the pet reaches Lv.120.
func _showcase_train() -> void:
	if _flow_pet().is_empty():stop_cycle("目标宠物不在随身队伍");return
	# Set before the first battle opens: with a high 经验倍率 that battle may
	# be the only one, and it must be shown, not resolved compactly.
	# A Lv1 pet is easily hurt: no HP stop line (carried pets are healed
	# between battles; a defeat is fought again, see _showcase_step).
	backend.session.clone_best_others = true
	showcase_show_battle = true
	if not start_pet_training(flow_pet_id,120,{},{"xp":int(profile_settings().xp),"compact":false,"hp":-1,"limit":1000000}):
		showcase_show_battle = false
		backend.session.clone_best_others = false
		stop_cycle("无法开始练级："+stop_reason);return
	_emit_status()

## Lv.120 reached: store and tidy as the full-speed cycle does, then say what
## became of the pet.
func _showcase_finished() -> void:
	showcase_show_battle = false
	backend.session.clone_best_others = false
	release_clone_override()
	var found := _flow_pet()
	if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
	var pet_id := flow_pet_id
	var template := int(found.get("template_id",-1))
	var actual := {"attack":int(found.attack),"defence":int(found.defence),"speed":int(found.speed),"max_hp":int(found.max_hp)}
	var predicted: Dictionary = showcase_current.get("prediction",{})
	_showcase_line("level","%s %s 练到120级：%s%s" % [str(found.get("name","")),pet_id,_stat_text(actual)," · 与预测一致" if actual==predicted else ""])
	complete_trained_pet(found)
	var outcome := ""
	for event in backend.session.release_events:
		if str(event.get("pet_id",""))==pet_id:outcome = "放生：%s" % str(event.get("reason",""))
	if outcome.is_empty():
		var reasons: Array = KeepRule.evaluate(KeepRule.species_pets(backend.session.snapshot(),template),flow_target_filter.get("keep_rule",{}),KeepRule.always_kept(backend.session.snapshot())).get("reasons",{}).get(pet_id,[])
		outcome = "留下：%s" % ("、".join(reasons) if not reasons.is_empty() else "已存入仓库")
		if flow_last_result.begins_with("未达标"):outcome = "未达标，"+outcome
	_showcase_line("released" if outcome.begins_with("放生") else "kept","%s %s %s" % [str(found.get("name","")),pet_id,outcome])
	if flow_phase=="compare":
		if hunt_running:stop_hunt(flow_reason)
		if not showcase_queue.is_empty():_showcase_line("dropped","收集完成，排队的 %d 只已放弃。" % showcase_queue.size())
		showcase_queue = []
		_emit_status()

## Settings the run changed for its training go back: 五人镜像队 and its
## composition.
func _showcase_restore() -> void:
	showcase_show_battle = false
	backend.session.clone_best_others = false
	release_clone_override()

## Back to searching: the next queued hit is taken on the following step.
func _showcase_resume() -> void:
	if not flow_stop_pending.is_empty():
		stop_cycle("本只练完，已停止：%s" % flow_stop_pending);return
	showcase_current = {}
	flow_pet_id = "";flow_matched_actor = {};flow_matched_index = -1;flow_capture_battle_id = ""
	flow_phase = "hunt"
	flow_reason = ""
	if not hunt_running and showcase_queue.is_empty() and not start_hunt(flow_hunt_request):
		stop_cycle(hunt_status);return
	_emit_status()

# ---- status ----------------------------------------------------------------

func status() -> Dictionary:
	return {
		"running":running,"compact":compact_active,"single_battle":single_battle,"capture_target":capture_target,
		"stop_reason":stop_reason,"battles":battles,"skipped":skipped,"earned_xp":earned_xp,"earned_pet_xp":earned_pet_xp,
		"turns":turns,"initial_level":initial_level,"settings":settings.duplicate(true),"training_pet_id":training_pet_id,
		"clone_override":clone_override_active,"previous_clone":previous_clone_enabled,"turn_text":turn_text,
		"finish_after_capture":finish_after_capture,"origin_map":origin_map,"origin_cell":[origin_cell.x,origin_cell.y],
		# Where the character is now (map -1 until a client has reported it).
		"position":{"map_id":position_map,"cell":[position_cell.x,position_cell.y]},
		"hunt":{"running":hunt_running,"rolls":hunt_rolls,"inspected":hunt_inspected,"best":hunt_best,"elapsed":hunt_elapsed,
			"filter":hunt_filter.duplicate(true),"status":hunt_status,"credit":hunt_credit,"last_hit":hunt_last_hit.duplicate(true),"map_id":hunt_map,"cell":[hunt_cell.x,hunt_cell.y],
			"fast":fast_hunt.running(),"fast_wanted":hunt_fast_wanted,"fast_note":hunt_fast_note,"fast_unavailable":fast_unavailable,
			"threads":fast_threads,"threads_used":threads_used(fast_threads),"cores":ServerSettings.cores()},
		"flow":{"phase":flow_phase,"reason":flow_reason,"pet_id":flow_pet_id,"stored_count":flow_stored_count,"last_result":flow_last_result,
			"last_stored_id":flow_last_stored_id,"last_stored_total":flow_last_stored_total,"map_id":flow_map,"cell":[flow_cell.x,flow_cell.y],
			"kept_count":flow_kept_count,"collected_count":flow_collected_count,"pruned_count":flow_pruned_count,"released_count":flow_released_count,"held_count":flow_held_count,"keep_auto":bool(flow_target_filter.get("keep_rule",{}).get("auto",false)),"predicted_rejects":flow_predicted_rejects,
			"best_predicted":flow_best_predicted.duplicate(),"skipped_count":flow_skipped_count,"skip_note":flow_skip_note,"showcase":flow_showcase,"queue":_queue_summary(),"queue_size":showcase_queue.size(),
			"survey":survey_status(),"thresholds":thresholds_text(),
			"log":showcase_log.duplicate(true),"stop_pending":flow_stop_pending,"queue_limit":queue_limit(),"show_battle":showcase_show_battle and backend.battle_open,"collect_target":collect_target_text(),"elapsed":elapsed_seconds(),"timer_running":timer_running},
	}

## 摸底 for the hunt window and the minimized bar: {active, remaining,
## seconds, candidates, names, pending (picks not yet caught), last}.
func survey_status() -> Dictionary:
	return {"active":not survey.is_empty(),"remaining":survey_remaining(),"seconds":survey_seconds,"candidates":survey.get("candidates",{}).size(),
		"names":survey.get("templates",[]).map(_template_name),"pending":_pending_picks().size(),"last":str(survey_last.get("text",""))}

## The cycle's thresholds as the player reads them, one species per line:
## 「扬奇洛斯：三围合 ≥ 最高 627 − 1 = 626，或 攻击 ≥ 最高 301 − 1 = 300」.
func thresholds_text() -> String:
	if not flow_active() or hunt_filter.is_empty():return ""
	var lines: PackedStringArray = []
	for id in _hunt_templates():
		var chosen := raw_filter_for(id)
		if not StatFilter.enabled(chosen):continue
		lines.append("%s：%s" % [_template_name(id),StatFilter.describe_thresholds(chosen,species_maxima(id))])
		if lines.size()>=3:break
	return "\n".join(lines)

func _emit_status() -> void:
	backend.emit_event({"type":"auto_status","status":status()})

func _emit_event(detail: Dictionary) -> void:
	backend.emit_event({"type":"auto_event","detail":detail})

func _set_position(command: Dictionary) -> void:
	if command.has("map_id"):
		position_map = int(command.map_id)
		var cell: Array = command.get("cell",[0,0])
		position_cell = Vector2i(int(cell[0]),int(cell[1]))

func _reply(ok: bool, reason: String) -> Dictionary:
	return {"ok":ok,"reason":"" if ok else reason}

## JSON object keys arrive as strings; stat filters are keyed by template id.
static func _int_keys(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:result[int(key)] = source[key]
	return result
