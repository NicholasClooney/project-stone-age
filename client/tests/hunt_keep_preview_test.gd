extends SceneTree
const Backend=preload("res://server/backend.gd")
const Progression=preload("res://server/progression.gd")
const Settings=preload("res://scripts/automation_settings.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func run()->void:
	var b=Backend.new();root.add_child(b);b.set_process(false)
	var a=b.automation
	var rng:=RandomNumberGenerator.new();rng.seed=784
	var entries:Array=[]
	for i in range(500):
		var troop:Dictionary=b.encounter_catalog.roll(100,Vector2i(637,493),rng)
		for slot in range(troop.get("enemies",[]).size()):
			var actor:Dictionary=troop.enemies[slot]
			if int(actor.level)!=1 or not actor.can_capture:continue
			if not entries.is_empty() and actor.template_id!=entries[0].actor.template_id:continue
			entries.append({"index":i,"slot":slot,"actor":actor,"troop":troop,"quality":{},"prediction":a._prediction(Progression.project_pet(actor,120))})
	check(entries.size()>10,"original encounter table supplies real seeded candidates")
	if entries.is_empty():quit(1);return
	var id:=str(entries[0].actor.template_id)
	var conditions:={}
	for metric in ["sum","attack","defence","speed"]:conditions[metric]={"enabled":false}
	var rule:={"auto":true,"tiers":1,"per_tier":1,"champions":0}
	check(b.handle({"type":"set_automation_settings","settings":{"hunt":{"preview_keep":true,"keep_rule":rule},"stat_filters":{id:{"conditions":conditions}}}}).ok,"server accepts opt-in shared preview and original conditions")
	a.flow_settings_overrides=b.session.automation_settings();a.flow_stat_filters=Settings.stat_filters(a.flow_settings_overrides)
	var owned:Dictionary=Progression.project_pet(entries[0].actor,120)
	owned.pet_id="pet-1";b.session._profile.pets=[owned];b.session._profile.next_pet_id=2
	a._showcase_add(entries[0].duplicate(true))
	check(a.showcase_queue.is_empty() and a.showcase_dropped_count==1,"exact stat tie keeps older owned UID and rejects future duplicate")
	var log:Dictionary=b.handle({"type":"pet_log","kind":"released"}).log
	check(not log.entries.is_empty() and log.entries[0].uncaught and str(log.entries[0].reason).contains("预计不会被保留"),"uncaught authoritative record explains predicted rejection")
	check(b.handle({"type":"set_automation_settings","settings":{"hunt":{"preview_keep":false}}}).ok,"preview has an independent server setting")
	a._showcase_add(entries[0].duplicate(true))
	check(a.showcase_queue.size()==1,"disabled preview preserves capture even if later tidy would release it")
	a.showcase_queue=[];b.session._profile.pets=[]
	b.handle({"type":"set_automation_settings","settings":{"hunt":{"preview_keep":true}}})
	entries.sort_custom(func(x,y):return int(x.prediction.attack)+int(x.prediction.defence)+int(x.prediction.speed)<int(y.prediction.attack)+int(y.prediction.defence)+int(y.prediction.speed))
	a._showcase_add(entries[0].duplicate(true));a._showcase_add(entries[-1].duplicate(true))
	check(a.showcase_queue.size()==1 and a.showcase_queue[0].prediction==entries[-1].prediction,"better pending tier displaces weaker pending candidate before capture")
	a.showcase_queue=[]
	b.handle({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":{"tiers":0,"champions":1,"champion_stats":["attack"]}}}})
	a.flow_settings_overrides=b.session.automation_settings()
	entries.sort_custom(func(x,y):return int(x.prediction.attack)<int(y.prediction.attack))
	a._showcase_add(entries[0].duplicate(true));a._showcase_add(entries[-1].duplicate(true))
	check(a.showcase_queue.size()==1 and a.showcase_queue[0].prediction.attack==entries[-1].prediction.attack,"single-stat champion survives even with no retained total-stat tiers")
	a.showcase_queue=[];a.flow_capture_only=true
	a._showcase_add(entries[0].duplicate(true));a._showcase_add(entries[-1].duplicate(true))
	check(a.showcase_queue.size()==2,"protected capture-only candidates bypass retention preview")
	a.showcase_queue=[];a.flow_capture_only=false
	b.handle({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":{"auto":false}}}})
	a.flow_settings_overrides=b.session.automation_settings()
	a._showcase_add(entries[0].duplicate(true));a._showcase_add(entries[-1].duplicate(true))
	check(a.showcase_queue.size()==2,"automatic tidy off leaves queue admission unchanged")
	check(not Settings.apply_patch({}, {"hunt":{"preview_keep":1}}).ok,"preview setting rejects non-boolean remote values")
	b.queue_free();await process_frame
	print("HUNT KEEP PREVIEW: %d failures"%failures);quit(1 if failures else 0)
