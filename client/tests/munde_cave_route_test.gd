extends "res://tests/original_fixed_guards_test.gd"
const Walk=preload("res://tests/support/water_route_driver.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
const KOLK="sainasu/event/event09@1200:97:75"
const HOTOR="sainasu/event/event10@1300:65:65"
const KATAN="sainasu/event/event11@1400:71:76"
const CHIEF="sainasu/event/event12@11107:24:6"
const GATE="genout/wpm_100_443_127@100:443:127"
func setup():
 var b=fresh()
 guards=[]
 for npc in b.quest_catalog.active_npcs():
  if str(npc.get("source_script","")) in ["100/sb_go.arg","100/sb_dan.arg"]:guards.append(npc)
 return b
func enter_original(b)->bool:
 # Public approach fixture only. Protected maps always use the real keyword,
 # report_position staircase route and actual guard settlement.
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 b.automation.position_changed(100,Vector2i(443,128))
 return bool(answer(b,b.handle({"type":"quest_talk","npc_id":GATE}),"在卡坦有梦德").get("ok",false))
func source_talk(b,npc:Dictionary)->Dictionary:
 if b.automation.position_map!=11101:
  if not enter_original(b):return {"ok":false,"reason":"Original keyword failed"}
 if not Walk.walk_near(b,npc,range(11101,11108)):return {"ok":false,"reason":"Original stairs failed"}
 return b.handle({"type":"quest_talk","npc_id":npc.id})
func talk(b,id:String)->Dictionary:
 if id!=CHIEF:return super.talk(b,id)
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 if not Walk.walk_near(b,npc,[11107]):return {"ok":false,"reason":"Original chief corridor not reachable"}
 return b.handle({"type":"quest_talk","npc_id":id})
func answer(b,r:Dictionary,text:String)->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"submit","text":text})
func seed_for(b,wanted:int)->int:
 var rng:=RandomNumberGenerator.new()
 for value in range(10000):
  rng.seed=value
  var drops:Array=[]
  for enemy in [527,526,528,529]:drops.append_array(b.encounter_catalog.actor(enemy,rng).generated_drops)
  if (wanted==0 and drops.is_empty()) or (wanted!=0 and wanted in drops):return value
 check(false,"source actor RNG seed found")
 return 0
func run()->void:
 var b=setup()
 check(guards.size()==2,"two actually bound original guards are imported")
 var modules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-modules.json"))
 var manifest:Dictionary={}
 for module in modules.modules:
  if str(module.id)=="munde-cave":manifest=module
 check(manifest.get("enabled_events",[]).map(func(event):return int(event))==[9,10,11,12],"Munde registration owns exactly9/10/11/12; wind has independent41/42 ownership")
 check([9,10,11,12].all(func(event):return event in b.quest_catalog.enabled_events),"all four Munde events remain enabled")
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(KOLK),b.session.snapshot()).is_empty(),"adult prerequisite still blocks high-level player")
 Rules.set_flag(b.session._profile,"ended",4,true) # Existing prerequisite fixture; original requests below.
 check(trade(b,KOLK).ok and trade(b,KATAN).ok and trade(b,HOTOR).ok,"three original requests")
 var q:Dictionary={}
 for job in b.quest_helper.snapshot(b).quests:
  if int(job.event)==9:q=job
 check(q.get("steps",[]).size()==9 and q.completion_detail.contains("先交卡坦"),"registered helper explains all original stages")
 var r:=talk(b,GATE);var before:Dictionary=b.session.snapshot()
 check(not answer(b,r,"在卡坦有梦德 ").ok and b.session.snapshot()==before,"exact original keyword rejects trailing space")
 r=talk(b,GATE);b.save_path="user://missing-munde-route/save.json"
 check(not answer(b,r,"在卡坦有梦德").ok and b.session.snapshot()==before,"keyword Warp save failure rolls back")
 b.save_path=""
 check(answer(b,talk(b,GATE),"在卡坦有梦德").ok and b.automation.position_map==11101 and b.automation.position_cell==Vector2i(33,29),"actual original entrance Warp")
 for wanted in [0,2482,2483]:
  var npc:Dictionary=guards[0 if wanted!=2483 else 1]
  r=source_talk(b,npc)
  b.encounter_rng.seed=seed_for(b,wanted)
  var started:Dictionary=choose(b,r,"yes")
  check(started.ok and b.battle_open,"actual source guard battle begins: "+str(started.get("reason","")))
  if not b.battle_open:b.free();quit(1);return
  check(b.session._pending.enemies.map(func(e):return int(e.source_enemy_id))==[527,526,528,529],"original four enemies preserve source order")
  check(preload("res://server/troop_art.gd").can_render(b.session._pending.enemies),"All original four-enemy battle art is imported")
  var drops:Array=[]
  for enemy in b.session._pending.enemies:drops.append_array(enemy.generated_drops)
  check(drops.is_empty() if wanted==0 else wanted in drops,"fixed source seed covers rare hit and miss")
  before=b.session.snapshot();b.save_path="user://missing-munde-route/save.json"
  fight(b)
  check(not b.battle_state.get("settled",false) and b.session.snapshot()==before,"failed real battle settlement grants neither drop nor Warp")
  check(not b.handle({"type":"battle_close"}).ok,"failed settlement remains pending")
  b.save_path=""
  check(b.handle({"type":"battle_close"}).ok,"same generated loot retries without reroll")
  for item in [2482,2483]:check(b.session.snapshot().original_items.count(item)==before.original_items.count(item)+drops.count(item),"actual kill reward settles original drop once")
  check(b.automation.position_map==11107 and b.automation.position_cell==Vector2i(23,35),"original victory Warp beyond guard")
  check(not choose(b,r,"yes").ok,"battle token cannot replay")
 check(not 2419 in b.session.snapshot().original_items and not 2420 in b.session.snapshot().original_items,"guard drops are not the village stones")
 check(trade(b,CHIEF).ok,"original chief gives both stones after route")
 before=b.session.snapshot();talk(b,HOTOR)
 check(b.session.snapshot().original_items==before.original_items and not Rules.flag(b.session.snapshot(),"ended",10),"first delivery cannot skip Katan")
 check(trade(b,KATAN).ok and Rules.flag(b.session.snapshot(),"ended",11),"Katan first")
 check(trade(b,HOTOR).ok and Rules.flag(b.session.snapshot(),"ended",12),"Hotor second records10/12")
 check(trade(b,KOLK).ok and Rules.flag(b.session.snapshot(),"ended",9) and 1357 in b.session.snapshot().original_items,"final Kolk1357 completes original chain")
 check(b.session.save_game("user://munde-route.json"),"whole route persists")
 var loaded=Session.new();check(loaded.load_game("user://munde-route.json") and loaded.snapshot().original_events==b.session.snapshot().original_events,"completed route flags survive real reload")
 b.free()
 await lan_guard()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://munde-route.json"+suffix))
 print("MUNDE CAVE ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
