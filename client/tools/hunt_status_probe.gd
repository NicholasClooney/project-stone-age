extends SceneTree
## Reproducible real-core workload; invoke with a private start marker/out file.
## Stops flow_step deliberately at the hunt phase to isolate queue churn from
## capture/training variance; every roll and release is still real authority.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const Codec = preload("res://network/codec.gd")
const ConditionsOff = preload("res://tests/support/conditions_off.gd")
var backend
var server
var marker := ""
var output := ""
var steps := 0
var started := 0
var next_step := 0
var core_usec := 0
var statuses := 0
var status_bytes := 0
var log_notifications := 0
var progress_supported := false
var ready := false
var finished := false
var rows: Array = []

func _initialize() -> void:call_deferred("setup")
func setup() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--marker="):marker=argument.trim_prefix("--marker=")
		if argument.begins_with("--out="):output=argument.trim_prefix("--out=")
	backend=Backend.new();root.add_child(backend);backend.set_process(false)
	backend.handle({"type":"grant_starter_pets"})
	var species: Array=ConditionsOff.area_species(100,Vector2i(637,493))
	var hunt := {"fast":false,"showcase":true,"queue":3,"total":-8,"offsets":[-2,-2,-2,-2],"templates":species,"clean_only":false,"mixed_if_stats":true}
	backend.handle({"type":"set_automation_settings","settings":ConditionsOff.patch(species).merged({"hunt":hunt,"capture":{"hp":100}})})
	backend.session.set_location(100,637,493)
	backend.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	if not backend.handle({"type":"auto_start","kind":"find_pet","map_id":100,"cell":[637,493]}).ok:
		push_error("probe start refused");quit(1);return
	backend.automation.hunt_run_seed=424242
	for method in backend.automation.get_method_list():
		if method.name=="_emit_status":progress_supported=method.args.size()>0
	backend.event.connect(func(message):
		if not ready or finished:return
		if message.type=="auto_status":
			statuses+=1;status_bytes+=Codec.encode(message).to_utf8_buffer().size()
		if message.type=="pet_log_changed":log_notifications+=1)
	server=WsServer.new(backend,0,"127.0.0.1");root.add_child(server)
	if server.start()!=OK:quit(1);return
	var file=FileAccess.open(output+".ready",FileAccess.WRITE)
	file.store_string(JSON.stringify({"port":server.port,"seed":424242,"steps":600,"scans_per_step":10}));file.close()
	print("PROBE READY: %d" % server.port)

func _process(_delta: float) -> bool:
	if server==null:return false
	if finished:
		backend.automation.tick_battle(0.0)
		backend._record_releases()
		return false
	if not ready:
		if not FileAccess.file_exists(marker):return false
		ready=true;started=Time.get_ticks_usec();next_step=started
	var now:=Time.get_ticks_usec()
	if now<next_step:return false
	var before:=Time.get_ticks_usec()
	for i in range(10):backend.automation.scan_once()
	backend.automation.hunt_elapsed=(Time.get_ticks_usec()-started)/1000000.0
	# Exercise the exact production progress call on both revisions.
	# Reflect the API once at startup, allowing identical harness on both revisions.
	if progress_supported:
		backend.automation._emit_status(true)
	else:backend.automation._emit_status()
	backend._record_releases()
	core_usec+=Time.get_ticks_usec()-before
	steps+=1;next_step=started+steps*16667
	if steps%60==0:rows.append({"step":steps,"seconds":(Time.get_ticks_usec()-started)/1000000.0,"statuses":statuses,"status_bytes":status_bytes,"core_usec":core_usec})
	if steps==600:
		finished=true
		var seconds: float=(Time.get_ticks_usec()-started)/1000000.0
		var result: Dictionary={"seed":424242,"steps":steps,"rolls":backend.automation.hunt_rolls,"inspected":backend.automation.hunt_inspected,"queue":backend.automation._queue_summary(),"uncaught":backend.release_log.entries().size(),"statuses":statuses,"status_bytes":status_bytes,"pet_log_notifications":log_notifications,"seconds":seconds,"core_usec":core_usec,"core_ms_per_second":core_usec/1000.0/seconds,"rows":rows}
		var file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
		print("PROBE FINISHED: ",JSON.stringify(result))
	return false
