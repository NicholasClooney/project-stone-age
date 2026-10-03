extends RefCounted
## Project convenience. Reuses ordinary walking pressure, RNG and troop selection.
const INTERVAL := 0.5
const LEASE := 5.0
var running := false
var reason := ""
var elapsed := 0.0
var lease := 0.0
var connection := 0
var map_id := -1
var cell := Vector2i.ZERO
var battle_id := ""
var saved_win := false
var encounters := 0
# Ephemeral diagnostic context, never serialized with the profile.
var diagnostic_command: Dictionary = {}

func unavailable(b) -> String:
	if b.stationary_party_member.is_valid() and b.stationary_party_member.call():return "组队中不能原地遇敌，请先离队。"
	if b.automation.running or b.automation.hunt_running or b.automation.flow_active() or b.quest_auto.running:return "请先停止自动练级、抓宠或自动任务。"
	var area: Dictionary = b.encounter_catalog.area_at(b.automation.position_map,b.automation.position_cell)
	if area.is_empty() or int(area.get("probability_max",0))<=0:return "当前位置没有地图随机遇敌。"
	if b.session.world_catalog.links(b.automation.position_map).has(b.automation.position_cell):return "传送点不能原地遇敌，请先离开传送点。"
	if bool(area.get("invalid_weights",false)) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:return "当前位置的原版遇敌条件尚不支持。"
	if int(b.session._profile.player.hp)<=0:return "倒下时不能原地遇敌。"
	return ""

func snapshot(b) -> Dictionary:
	var why := unavailable(b)
	return {"running":running,"available":why.is_empty(),"reason":why if not why.is_empty() else reason,"interval":INTERVAL,"encounters":encounters,"stop_reason":reason if not running else ""}

func start(b, command: Dictionary) -> Dictionary:
	if not command.get("enabled") is bool:return b._reject("开关必须为布尔值。")
	if not command.enabled:
		stop(b,"已关闭原地遇敌。")
		return {"ok":true}
	var why := unavailable(b)
	if not why.is_empty():return b._reject(why)
	if b.battle_open or not b.session._pending.is_empty() or not b.original_quests.pending.is_empty():return b._reject("请先结束战斗或对话。")
	if bool(b.session._profile.get("no_random_encounters",false)):
		var reply: Dictionary = b._cmd_no_random_encounters({"enabled":false})
		if not reply.ok:return reply
	running = true
	reason = "胜利后继续遇敌；出招仍由你控制。"
	elapsed = 0.0;lease = LEASE;encounters = 0
	connection = int(command.get("_quest_connection",0))
	map_id = b.automation.position_map;cell = b.automation.position_cell
	battle_id = "";saved_win = false
	b.publish()
	return {"ok":true}

func keepalive(b, command: Dictionary) -> Dictionary:
	if running and int(command.get("_quest_connection",0))==connection:lease = LEASE
	return {"ok":true,"stationary":snapshot(b)}

func stop(b, why: String) -> void:
	if not running:return
	running = false;reason = why;elapsed = 0.0
	audit(b,"pause" if diagnostic_command.get("type","")=="stationary_pause" else "stop",why)
	b.publish()

func command(b, type: String) -> void:
	if type in ["warp","field_step","wild_encounter","open_battle","begin_battle","start_battle_config","start_wild_battle_config","start_wild_battle","auto","auto_start","hunt_start","start_hunt","flow_start","quest_auto_start","quest_talk","quest_choose","quest_visit"]:
		stop(b,"移动、对话或其他自动操作停止了原地遇敌。")

func settled(b, state: Dictionary, saved: bool) -> void:
	if not running or battle_id.is_empty() or str(state.get("battle_id",""))!=battle_id:return
	if not saved:
		stop(b,"战斗保存失败，已停止原地遇敌；请先处理结算。")
	elif str(state.get("outcome",""))!="win":
		stop(b,"战斗未获胜，已停止原地遇敌。")
	else:saved_win = true

func tick(b, delta: float) -> void:
	if not running:return
	diagnostic_command = {"type":"tick"}
	_tick(b,delta)
	diagnostic_command = {}

func _tick(b, delta: float) -> void:
	lease -= maxf(0,delta)
	if lease<=0:
		stop(b,"发起设备已断线或暂停，已停止原地遇敌。")
		return
	var why := unavailable(b)
	if not why.is_empty():stop(b,why);return
	if map_id!=b.automation.position_map or cell!=b.automation.position_cell:
		stop(b,"位置改变，已停止原地遇敌。");return
	if bool(b.session._profile.get("no_random_encounters",false)):
		stop(b,"不遇敌已开启。");return
	if not battle_id.is_empty():
		if b.battle_open:
			if str(b.battle_state.get("battle_id",""))!=battle_id or (not b.battle.snapshot().active and not saved_win):
				stop(b,"战斗未成功结算，已停止原地遇敌。")
			return
		if not saved_win or not b.session._pending.is_empty():
			stop(b,"战斗未成功结算，已停止原地遇敌。");return
		if not b.save():
			stop(b,"战后保存失败，已停止原地遇敌。");return
		battle_id = "";saved_win = false;elapsed = 0.0
		return
	if b.battle_open or not b.session._pending.is_empty():stop(b,"其他战斗停止了原地遇敌。");return
	elapsed += maxf(0,delta)
	if elapsed<INTERVAL:return
	# At most one step per frame, no catch-up burst after a stalled server.
	elapsed = 0.0
	var reply: Dictionary = b._cmd_field_step({"map_id":map_id,"cell":[cell.x,cell.y],"encounter":true})
	if bool(reply.get("battle",false)):
		battle_id = str(b.battle_state.get("battle_id",""))
		encounters += 1
		b.publish()
	elif bool(reply.get("hit",false)):
		stop(b,"原版遇敌数据或素材不可用，已停止。")

## One compact stdout record at a transition; whitelist fields, never tokens,
## request payloads, filesystem paths or the character profile.
func audit(b, event: String, why: String, source: Dictionary = {}) -> void:
	var origin: Dictionary = diagnostic_command if source.is_empty() else source
	var record := {"event":event,"time_utc":Time.get_datetime_string_from_system(true),"monotonic_ms":Time.get_ticks_msec(),
		"character":b.account_name,"reason":why,"source":str(origin.get("type","server")),
		"connection":origin.get("_quest_connection",null),"owner_connection":connection,
		"battle_id":battle_id,"active":bool(b.battle.snapshot().get("active",false)),"running":running,
		"pause":str(origin.get("type",""))=="stationary_pause","saved_win":saved_win,"encounters":encounters}
	if origin.get("type","")=="auto":record.operation=str(origin.get("name",""))
	if origin.get("type","")=="stationary_pause":
		# Client observations aid diagnosis; they never authorize server state.
		for field in ["paused_input","battle_visible","menu_visible","battle_open"]:
			if origin.has(field):record["client_"+field]=bool(origin[field])
	print("[stationary] "+JSON.stringify(record))
