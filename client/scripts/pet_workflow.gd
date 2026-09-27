extends Node
## One local cycle. Delegates battle actions and rewards to existing authorities.
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
func active() -> bool:return phase in ["hunt","capture","train"]
func start_cycle(species_key: String="") -> bool:
	if active():return false
	if world.battle_session.snapshot().get("active",false) or world.battle_view.visible or world.moving or world.area_transition_busy:
		reason="请先结束战斗或移动，再开始一轮找宠。";world.message.text=reason;return false
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		reason="宠物栏已满，请自行存放伙伴后再开始。";world.message.text=reason;return false
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

func matched(index: int, actor: Dictionary) -> void:
	if phase!="hunt":return
	matched_index=index;matched_actor=actor.duplicate(true)
	capture_battle_id=str(world.battle_session.snapshot().get("battle_id",""))
	phase="capture"
	world.training_helper.start_capture_battle(index,true)
	if not world.training_helper.running:stop_cycle("无法开始自动捕捉，请手动处理当前战斗。")

func stop_cycle(message: String="已手动停止") -> void:
	phase="paused";reason=message
	if world.pet_hunt_menu.running:world.pet_hunt_menu.stop_hunt(message)
	if world.training_helper.running:world.training_helper.stop_training(message)
	world.message.text="找宠流程暂停："+message

func _process(_delta: float) -> void:advance()
func advance() -> void:
	if not active():return
	if int(world.data.map_id)!=origin_map or world.cell!=origin_cell or world.moving or world.area_transition_busy:
		stop_cycle("位置发生变化；请在当前位置重新开始。");return
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
		if not helper.start_pet_training(pet_id,120):stop_cycle(helper.stop_reason)
		return
	if phase=="train":
		if helper.stop_reason!="目标宠物已达到等级目标":stop_cycle(helper.stop_reason);return
		var found: Dictionary={}
		for pet in world.session.snapshot().pets:
			if str(pet.get("pet_id",""))==pet_id:found=pet
		if found.is_empty() or int(found.level)<120:stop_cycle("目标宠物未达到120级，请手动检查。");return
		phase="compare";reason="新伙伴已达到120级，请对比后自行决定去留。"
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
	phase="paused"
	world.pet_hunt_menu.running=false
	world.training_helper.release_clone_override()
	world.training_helper.running=false
	world.training_helper.compact_active=false
	world.battle_session.set_capture_assist(false)
	return reason
