extends Node
## Local capture/train cycles. Stat failures store and repeat; a match stops for comparison.
## Hunt-stored pets are flagged and pruned to the per-metric rolling keep (e.g. top 15 sum + top 5 attack).
## Battle actions and rewards stay with existing authorities.
const StatFilter=preload("res://scripts/pet_stat_filter.gd")
const Progression=preload("res://server/progression.gd")
var stat_filter_snapshot: Dictionary = {}
var target_stat_filter: Dictionary = {}
# With a filter's stop_after other than 1, matches are stored and the hunt goes
# on until this run keeps stop_after of them (0 = until stopped manually).
var kept_count := 0
var collected_count := 0
var stored_count := 0
var pruned_count := 0
var predicted_rejects := 0
var best_predicted: Dictionary = {}
var last_result := ""
var last_stored_id := ""
var last_stored_total := 0
var timer_clock: Callable = Time.get_ticks_msec
var timer_started_msec := 0
var timer_frozen_seconds := 0.0
var timer_running := false
var world: Node
var phase := "idle"
var reason := ""
var pet_id := ""
var origin_map := -1
var origin_cell := Vector2i.ZERO
var known_ids: Dictionary = {}
var matched_actor: Dictionary = {}
var matched_index := -1
var capture_battle_id := ""

func configure(owner: Node) -> void:world=owner
func elapsed_seconds() -> float:
	return maxf(0.0,(int(timer_clock.call())-timer_started_msec)/1000.0) if timer_running else timer_frozen_seconds
func elapsed_text() -> String:
	var seconds:=int(elapsed_seconds())
	return "%02d:%02d:%02d" % [seconds/3600,(seconds/60)%60,seconds%60]
func start_timer() -> void:
	timer_started_msec=int(timer_clock.call());timer_frozen_seconds=0.0;timer_running=true
func freeze_timer() -> void:
	timer_frozen_seconds=elapsed_seconds();timer_running=false
func active() -> bool:return phase in ["hunt","capture","train","restart"]
func start_cycle(species_key: String="", continuing: bool=false) -> bool:
	if active():return false
	if world.battle_session.snapshot().get("active",false) or world.battle_view.visible or world.moving or world.area_transition_busy:
		reason="请先结束战斗或移动，再开始一轮找宠。";world.message.text=reason;return false
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		reason="宠物栏已满，请自行存放伙伴后再开始。";world.message.text=reason;return false
	if not continuing:
		world.pet_hunt_menu.commit_stat_settings()
		stat_filter_snapshot=world.pet_stat_filters.duplicate(true)
		stored_count=0;pruned_count=0;kept_count=0;collected_count=0;predicted_rejects=0;best_predicted={};last_result="";last_stored_id=""
		start_timer()
	world.adventure_menu.hide();world.paused_input=false
	origin_map=int(world.data.map_id);origin_cell=world.cell
	known_ids.clear();pet_id="";matched_actor={};matched_index=-1;capture_battle_id="";reason=""
	for pet in world.session.snapshot().pets:known_ids[str(pet.pet_id)]=true
	phase="hunt"
	if not world.pet_hunt_menu.visible:world.pet_hunt_menu.open_menu()
	if not species_key.is_empty():
		var template_id:=92 if species_key=="blue" else int(species_key.trim_prefix("original_"))
		var choice: int=world.pet_hunt_menu.species.get_item_index(template_id)
		if choice<0 or world.pet_hunt_menu.species.is_item_disabled(choice):
			stop_cycle("当前地点和等级条件没有此品种；请自行前往合适地点或调整找宠条件。");return false
		world.pet_hunt_menu.species.select(choice)
	# Starting from the already-open hunt panel must retain its modal lock.
	world.clear_input();world.paused_input=true
	world.pet_hunt_menu.start_hunt()
	if not world.pet_hunt_menu.running:
		stop_cycle(world.pet_hunt_menu.status.text);return false
	return true

func collect_target_text() -> String:
	var stop_after:=int(target_stat_filter.get("stop_after",1))
	return "不限" if stop_after<=0 else str(stop_after)

func filter_for(template_id: int) -> Dictionary:
	return stat_filter_snapshot.get(template_id,StatFilter.defaults(template_id))

# Hunt-time gate: compute the exact Lv.120 stats from the wild pet's own seed and
# only let pets that will meet the conditions through to capture.
func accepts_prediction(actor: Dictionary) -> bool:
	var settings:=filter_for(int(actor.get("template_id",-1)))
	if not StatFilter.enabled(settings):return true
	var projected:=Progression.project_pet(actor,120)
	var total:=int(projected.attack)+int(projected.defence)+int(projected.speed)
	if best_predicted.is_empty() or total>int(best_predicted.sum) or (total==int(best_predicted.sum) and int(projected.attack)>int(best_predicted.attack)):
		best_predicted={"sum":total,"attack":int(projected.attack)}
	if StatFilter.evaluate(projected,settings):return true
	predicted_rejects+=1
	return false

func matched(index: int, actor: Dictionary) -> void:
	if phase!="hunt":return
	target_stat_filter=filter_for(int(actor.get("template_id",-1))).duplicate(true)
	matched_index=index;matched_actor=actor.duplicate(true)
	capture_battle_id=str(world.battle_session.snapshot().get("battle_id",""))
	phase="capture"
	world.training_helper.start_capture_battle(index,true)
	if not world.training_helper.running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。")

func stop_cycle(message: String="已手动停止") -> void:
	freeze_timer()
	phase="paused";reason=message
	if world.pet_hunt_menu.running:world.pet_hunt_menu.stop_hunt(message)
	if world.training_helper.running:world.training_helper.stop_training(message)
	world.message.text="找宠流程暂停："+message

func _process(_delta: float) -> void:advance()
func advance() -> void:
	if not active():return
	if int(world.data.map_id)!=origin_map or world.cell!=origin_cell or world.moving or world.area_transition_busy:
		stop_cycle("位置发生变化；请在当前位置重新开始。");return
	if phase=="restart":
		phase="idle"
		if not start_cycle("",true):stop_cycle(reason)
		return
	if phase=="hunt":
		if not world.pet_hunt_menu.running:stop_cycle(world.pet_hunt_menu.status.text)
		return
	var helper=world.training_helper
	if helper.running:return
	if phase=="capture":
		# Only the normal single-battle completion permits continuation; Stop is final.
		if helper.stop_reason!="本场自动战斗已完成":stop_cycle(helper.stop_reason);return
		var battle: Dictionary=world.battle_session.snapshot()
		if battle.get("active",false) or str(battle.get("battle_id",""))!=capture_battle_id:
			stop_cycle("捕捉战斗状态已改变。");return
		var enemies: Array=battle.get("enemies",[])
		if matched_index<0 or matched_index>=enemies.size() or not enemies[matched_index].get("captured",false):
			stop_cycle("目标未捕获；未改抓其他敌人。");return
		var fresh: Array=[]
		var pets: Array=world.session.snapshot().pets
		for i in range(pets.size()):
			if not known_ids.has(str(pets[i].get("pet_id",""))):fresh.append(i)
		if fresh.size()!=1 or not same_capture(pets[fresh[0]],matched_actor):
			stop_cycle("无法唯一确认新捕获伙伴，请手动检查宠物栏。");return
		pet_id=str(pets[fresh[0]].pet_id)
		if not world.session.select_pet(int(fresh[0])):stop_cycle("新伙伴无法出战。");return
		world.refresh_companion();world.checkpoint()
		phase="train"
		# Growth is seeded per pet and level, so instant levelling equals battle training.
		if not world.session.level_pet_to(pet_id,120):stop_cycle("无法升至120级："+str(world.session.last_error));return
		world.refresh_companion();world.checkpoint()
		var leveled: Dictionary={}
		for pet in world.session.snapshot().pets:
			if str(pet.get("pet_id",""))==pet_id:leveled=pet
		complete_trained_pet(leveled)
		return
	if phase=="train":
		if helper.stop_reason!="目标宠物已达到等级目标":stop_cycle(helper.stop_reason);return
		var found: Dictionary={}
		for pet in world.session.snapshot().pets:
			if str(pet.get("pet_id",""))==pet_id:found=pet
		if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
		complete_trained_pet(found)

func complete_trained_pet(found: Dictionary)->void:
	if phase!="train":return
	# Use settled actual attributes, never the forecast or a different pet's ID.
	if str(found.get("pet_id",""))!=pet_id or int(found.get("level",0))<120:
		stop_cycle("目标宠物未达到120级，请手动检查。");return
	var filtered:=StatFilter.enabled(target_stat_filter)
	var passed:=StatFilter.evaluate(found,target_stat_filter)
	last_result="%s · %s" % [pet_id,StatFilter.describe(found,target_stat_filter)] if filtered else "新伙伴已达到120级"
	if filtered and not passed:
		var index:=-1
		var pets:Array=world.session.snapshot().pets
		for i in range(pets.size()):
			if str(pets[i].get("pet_id",""))==pet_id:index=i;break
		if index<0 or not world.session.store_pet(index,true):
			stop_cycle("未达标但无法存仓："+str(world.session.last_error));return
		stored_count+=1;last_stored_id=pet_id;last_stored_total=int(found.attack)+int(found.defence)+int(found.speed);last_result="未达标已存仓 · "+last_result
		pruned_count+=world.session.prune_hunt_pets(int(found.get("template_id",-1)),StatFilter.keep_counts(target_stat_filter))
		world.refresh_companion();world.checkpoint()
		world.message.text=last_result
		# A separate frame leaves cancellation/reload a boundary before restarting.
		phase="restart";reason=last_result
		return
	var stop_after:=int(target_stat_filter.get("stop_after",1))
	if filtered and stop_after!=1:
		# Keep the qualifier in the warehouse (never flagged for pruning) and continue.
		var keep_index:=-1
		var carried:Array=world.session.snapshot().pets
		for i in range(carried.size()):
			if str(carried[i].get("pet_id",""))==pet_id:keep_index=i;break
		if keep_index<0 or not world.session.store_pet(keep_index,true):
			stop_cycle("达标但无法存仓："+str(world.session.last_error));return
		kept_count+=1
		collected_count+=1
		pruned_count+=world.session.prune_hunt_pets(int(found.get("template_id",-1)),StatFilter.keep_counts(target_stat_filter))
		world.refresh_companion();world.checkpoint()
		last_result="达标已存仓 · "+last_result
		if stop_after>0 and collected_count>=stop_after:
			freeze_timer()
			phase="compare";reason="收集完成：本轮找到%d只达标宠物 · %s"%[collected_count,last_result]
			world.paused_input=true
			world.adventure_menu.open_pet_comparison(pet_id)
			world.message.text=reason
			return
		world.message.text=last_result
		phase="restart";reason=last_result
		return
	freeze_timer()
	phase="compare";reason=("已达标 · "+last_result) if filtered else "新伙伴已达到120级，请对比后自行决定去留。"
	world.paused_input=true
	world.adventure_menu.open_pet_comparison(pet_id)
	world.message.text=reason

static func same_capture(pet: Dictionary, actor: Dictionary) -> bool:
	for key in ["template_id","species","level","growth_weights","growth_seed","growth_rank","base_stats"]:
		if actor.has(key) and pet.get(key)!=actor[key]:return false
	return true

func prepare_scene_reload() -> String:
	if not active():return ""
	# A defeat may already be inside return_from_battle: never settle or reopen
	# the battle here. Quiesce the old controls before the UI tree is rebuilt.
	reason="战斗失败，流程已暂停。" if world.battle_session.snapshot().get("outcome","")=="defeat" else "地图发生变化，流程已暂停。"
	freeze_timer()
	phase="paused"
	world.pet_hunt_menu.running=false
	world.training_helper.release_clone_override()
	world.training_helper.running=false
	world.training_helper.compact_active=false
	world.battle_session.set_capture_assist(false)
	return reason
