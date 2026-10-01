extends SceneTree
## Finished fast-hunt helpers are reaped (server/fast_hunt.gd): a long hunt
## used to leave one zombie per hit or restart until the user's process limit
## was exhausted.
var failures := 0

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func zombies() -> int:
	var output: Array = []
	OS.execute("ps",["-A","-o","ppid=,stat="],output)
	var count := 0
	for line in str(output[0] if not output.is_empty() else "").split("\n",false):
		var parts := line.strip_edges().split(" ",false)
		if parts.size()>=2 and int(parts[0])==OS.get_process_id() and parts[1].begins_with("Z"):count += 1
	return count

func _initialize() -> void:
	var hunt = load("res://server/fast_hunt.gd").new()
	var before := zombies()
	for i in range(20):
		hunt.pid = OS.create_process("/bin/sleep",["0"])
		hunt._forget_pid()
	var deadline := Time.get_ticks_msec()+3000
	while not hunt._unreaped.is_empty() and Time.get_ticks_msec()<deadline:
		OS.delay_msec(20)
		hunt.reap()
	check(hunt._unreaped.is_empty(),"every finished helper is reaped")
	check(zombies()<=before,"no zombie children are left behind (%d before, %d after)" % [before,zombies()])
	hunt.pid = OS.create_process("/bin/sleep",["5"])
	hunt.stop()
	deadline = Time.get_ticks_msec()+3000
	while not hunt._unreaped.is_empty() and Time.get_ticks_msec()<deadline:
		OS.delay_msec(20)
		hunt.reap()
	check(hunt._unreaped.is_empty() and zombies()<=before,"a stopped (killed) helper is reaped too")
	print("FAST HUNT REAP: %d failures" % failures)
	quit(1 if failures else 0)
