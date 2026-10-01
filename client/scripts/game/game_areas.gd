extends RefCounted
## Maps for the game scene (scripts/game.gd): building the world for the
## current map, loading another map (downloading its packs on the web), the
## fade between maps, exits and arrival rules, placing the character at
## startup, and the developer shortcuts to a map. The map data, terrain and
## actors stay on the game; see docs/technical/game-scripts.md.
const LegacyActor = preload("res://scripts/legacy_actor.gd")
const LegacyGround = preload("res://scripts/legacy_ground.gd")
const MapFile = preload("res://scripts/map_file.gd")
const MusicTracks = preload("res://scripts/music_tracks.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func area_name() -> String:
	return str(game.data.get("name","萨姆吉尔村"))

func display_cell() -> Vector2i:
	var origin: Array = game.data.get("origin",[0,0])
	return game.cell+Vector2i(int(origin[0]),int(origin[1]))

func build_world() -> void:
	# Player characters' walking art is read per character when drawn (legacy_actor.gd).
	if game.character_catalog.is_empty():game.character_catalog = preload("res://scripts/character_art.gd").index()
	game.terrain = LegacyGround.new()
	game.terrain.world = game
	game.terrain.fill(game.data.ground)
	game.add_child(game.terrain)
	game.actors = Node2D.new()
	game.actors.y_sort_enabled = true
	game.actors.z_index = 1
	game.add_child(game.actors)
	game.player = LegacyActor.new()
	game.player.world = game
	game.player.character_id = str(game.session.snapshot().get("character_id","100000"))
	if not game.character_catalog.get("characters",{}).has(game.player.character_id) and not game.data.get("characters",{}).has(game.player.character_id):game.player.character_id = "100000"
	game.player.position = game.project(game.logical_position)
	game.actors.add_child(game.player)
	game.camera = Camera2D.new()
	game.camera.position = Vector2(0,-25)
	game.camera.position_smoothing_enabled = true
	game.camera.position_smoothing_speed = 10
	game.player.add_child(game.camera)
	game.navigation.clear()
	game.navigation.region = Rect2i(0,0,int(game.data.width),int(game.data.height))
	game.navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	game.navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	game.navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	game.navigation.update()
	# While the map is built nothing else blocks a cell (the resident and the
	# travel overlay are placed afterwards), so only the map's own flags count.
	var width := int(game.data.width)
	var blocked: PackedByteArray = game.data.blocked
	for index in range(blocked.size()):
		if blocked[index]!=0:game.navigation.set_point_solid(Vector2i(index%width,index/width))
	game.props = preload("res://scripts/legacy_props.gd").new()
	game.props.world = game
	game.actors.add_child(game.props)
	if int(game.data.map_id) in [1000,1002]:
		game.setup_npc()
	game.pet_trail.assign([game.cell,game.cell])
	game.pet_follower = null

func switch_area(wilderness: bool, destination: Vector2i) -> bool:
	return load_area_id(100 if wilderness else 1000,destination+Vector2i(592,448) if wilderness and game.world_catalog.maps.has("100") else destination)

func load_area_id(map_id: int, destination: Vector2i) -> bool:
	# A 组队 member goes only where the server moves it (after the leader).
	if game.party_locked() and [map_id,destination]!=game._followed:
		game.message.text = GameScene.PARTY_LOCKED_TEXT
		return false
	var needed := area_packs(map_id)
	if not game.asset_packs.is_ready(needed):
		_load_area_after_download(map_id,destination,needed)
		return true
	var file := game.world_catalog.file(map_id)
	if not FileAccess.file_exists(file):
		game.message.text = "Import the wilderness assets first; see README.md."
		return false
	# The packed map is a few MB, so holding the old one while the new one is
	# checked no longer doubles the peak (docs/technical/memory-baseline.md).
	var next_data := MapFile.load_map(file)
	if next_data.is_empty():
		return false
	preload("res://scripts/perf_registry.gd").track_manifest("当前地图",MapFile.file_size(file))
	var width := int(next_data.width)
	var height := int(next_data.height)
	if destination.x<0 or destination.y<0 or destination.x>=width or destination.y>=height or int(next_data.blocked[destination.y*width+destination.x])!=0:
		return false
	var previous_zoom: Vector2 = game.camera.zoom
	game.clear_input()
	# Residents and their dialogue belong to the old map.
	if game.dialogue.visible:game.close_dialogue()
	if is_instance_valid(game.world_travel) and is_instance_valid(game.world_travel.overlay):game.world_travel.overlay.queue_free()
	for node in [game.terrain,game.actors]:
		game.remove_child(node)
		node.queue_free()
	game.data = next_data
	# Map tiles and props the next map does not draw are let go (a texture
	# still on screen stays alive through its node until that is freed); the
	# few others, like actor frames, load again when next drawn.
	var keep: Dictionary = next_data.get("images",{})
	for key in game.textures.keys():
		if not keep.has(key):
			game.textures.erase(key)
			preload("res://scripts/perf_registry.gd").forget("map",key)
	game.world_travel = null
	game.npc_data.clear()
	game.npc_cell = Vector2i(-1,-1)
	game.npc = null
	game.npc_sprite = null
	game.cell = destination
	game.arrival_lock = destination
	game.from_cell = destination
	game.target_cell = destination
	game.logical_position = Vector2(destination)
	game.moving = false
	game.paused_input = game._panel_open() or game.automation_minimized()
	game.marker_cell = Vector2i(-1,-1)
	game.field_steps = 0
	build_world()
	game.camera.zoom = previous_zoom
	game.refresh_map_ui()
	if [int(game.data.map_id),game.cell]!=game._followed:game.link.request({"type":"report_position","map_id":int(game.data.map_id),"cell":[game.cell.x,game.cell.y],"map_changed":true,"client":game._client_id},game._on_map_reported)
	game.camera.reset_smoothing()
	game.area_music = game.exploration_music()
	game.set_music(game.area_music)
	game.queue_redraw()
	game.refresh_companion()
	game.checkpoint()
	for link_info in game.world_catalog.links(map_id).values():game.asset_packs.prefetch(area_packs(int(link_info.to_map)))
	return true

## Packs a map needs: its data, tiles, residents and music.
func area_packs(map_id: int) -> Array:
	var packs: Array = game.asset_packs.map_packs(map_id).duplicate()
	var music_path: String = game._audio.map_music(map_id)
	if not music_path.is_empty():
		var pack: String = game.asset_packs.file_pack(MusicTracks.path("res://assets/legacy/"+music_path))
		if not pack.is_empty() and not packs.has(pack):packs.append(pack)
	return packs

func _load_area_after_download(map_id: int, destination: Vector2i, needed: Array) -> void:
	game.clear_input()
	game.paused_input = true
	var ok := await game.await_packs(needed,"地图 %s" % str(game.world_catalog.info(map_id).get("name",map_id)))
	game.paused_input = false
	if ok:load_area_id(map_id,destination)
	elif is_instance_valid(game.message):game.message.text = "地图素材下载失败，请稍后再试。"

func transition_area(map_id: int, destination: Vector2i) -> bool:
	if game.area_transition_busy:return false
	game.area_transition_busy = true
	game.paused_input = true
	game.clear_input()
	_run_area_transition(map_id,destination)
	return true

func _run_area_transition(map_id: int, destination: Vector2i) -> void:
	await game.map_transition.transition(func():
		var changed := load_area_id(map_id,destination)
		game.paused_input = true
		return changed)
	game.area_transition_busy = false
	game.paused_input = false
	game.clear_input()

func walk_to_exit() -> void:
	if game.paused_input:
		return
	var links: Dictionary = game.world_catalog.links(int(game.data.map_id))
	var closest := Vector2i(-1,-1)
	var distance := INF
	for point in links:
		var link: Dictionary = links[point]
		if int(game.data.map_id) in [1000,2000,3000,4000] and not game.world_catalog.field(int(link.to_map)):continue
		if game.cell.distance_squared_to(point)<distance:
			closest=point;distance=game.cell.distance_squared_to(point)
	if closest.x>=0:game.walk_to(closest)

func handle_arrival() -> bool:
	game.report_position()
	game.pet_trail.append(game.cell)
	while game.pet_trail.size()>3:game.pet_trail.pop_front()
	if game.cell==game.arrival_lock:return false
	game.arrival_lock = Vector2i(-1,-1)
	var links: Dictionary = game.world_catalog.links(int(game.data.map_id))
	if links.has(game.cell):
		var link: Dictionary = links[game.cell]
		if preload("res://scripts/passage_rules.gd").requires_permit(int(game.data.map_id),int(link.to_map)) or bool(link.get("requires_travel_pass",false)):
			if not game.session.has_travel_pass():
				game.message.text = "穿过海底关卡需要通行证。"
				return false
			game.paused_input = true
			game.clear_input()
			game.link.request({"type":"check_passage","from_map":int(game.data.map_id),"to_map":int(link.to_map)},func(reply: Dictionary):
				game.paused_input = false
				if reply.get("ok",false):transition_area(int(link.to_map),Vector2i(int(link.target[0]),int(link.target[1])))
				else:game.message.text = str(reply.get("reason","穿过海底关卡需要通行证。")))
			return true
		return transition_area(int(link.to_map),Vector2i(int(link.target[0]),int(link.target[1])))
	if game.world_catalog.field(int(game.data.map_id)) and game.random_encounters:
		game.field_steps += 1
		var can_battle := not game.moving and not game.paused_input and not game.area_transition_busy and is_instance_valid(game.battle_view) and not game.battle_view.visible
		game.last_encounter_error=""
		return bool(game.link.request({"type":"field_step","map_id":int(game.data.map_id),"cell":[game.cell.x,game.cell.y],"encounter":can_battle},game._on_encounter_reply).get("battle",false))
	return false

## Places the character at startup: where a running backend already has it
## (another device or automation may have moved it since the last save),
## else the saved location. Arriving there is not travel, so it is not
## reported as a map change, which would stop running automation.
func restore_location() -> void:
	var location: Dictionary = game.session.snapshot().location
	var map_id := int(location.map_id)
	var point := Vector2i(int(location.x),int(location.y))
	if map_id==100 and not game.world_catalog.maps.has("100"):point -= Vector2i(592,448)
	var live: Dictionary = game.state.automation.get("position",{})
	if not game.link.is_local() and int(live.get("map_id",-1))>=0:
		map_id = int(live.map_id)
		point = Vector2i(int(live.cell[0]),int(live.cell[1]))
	game._followed = [map_id,point]
	if not load_area_id(map_id,point):
		load_area_id(1000,GameScene.SPAWN)

func dev_visit(id: int) -> bool:
	if is_instance_valid(game.travel_router):game.travel_router.cancel("开发传送取消了自动寻路。")
	if game.paused_input or game.area_transition_busy or game.battle_view.visible:return false
	var info: Dictionary = game.world_catalog.info(id)
	if info.is_empty():return false
	var spawn: Array = info.spawn
	return load_area_id(id,Vector2i(int(spawn[0]),int(spawn[1])))

func dev_go_villager() -> void:
	if game.paused_input or game.area_transition_busy:return
	if load_area_id(1000,Vector2i(92,72)):game.approach_npc()

func dev_go_adventure() -> void:
	if game.paused_input or game.area_transition_busy:return
	if int(game.data.map_id)==1000:switch_area(true,Vector2i(45,45))
	else:load_area_id(1000,GameScene.SPAWN)

func dev_go_shop() -> void:
	if game.paused_input or game.area_transition_busy:return
	if load_area_id(1002,Vector2i(16,15)):game.approach_npc()
