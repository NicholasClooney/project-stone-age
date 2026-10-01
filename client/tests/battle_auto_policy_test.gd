extends SceneTree
const Policy=preload("res://scripts/battle_auto_policy.gd")
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():
 var state={"enemies":[{"hp":100,"max_hp":100,"level":5,"can_capture":true},{"hp":10,"max_hp":100,"level":1,"can_capture":true}],"pets":[{"hp":20,"level":4},{"hp":20,"level":1},{"hp":0,"level":1}],"active_pet":0,"ride_pet":-1}
 var settings={"preset":"capture","capture_hp":20,"capture_pet":-1,"capture_pet_max_level":10}
 var plan=Policy.decide(state,settings,0)
 check(plan.action=="switch" and plan.switch==1 and plan.pet=="defend","switch to lowest living pet through ordinary guarded turn")
 state.active_pet=1;plan=Policy.decide(state,settings,0)
 check(plan.action=="defend" and plan.pet=="attack" and plan.target==0,"leader guards while lowest pet attacks exact selected target")
 state.enemies[0].hp=20;plan=Policy.decide(state,settings,0)
 check(plan.action=="capture" and plan.pet=="defend","at configurable threshold capture and pet guards")
 state.enemies[0].captured=true
 check(Policy.decide(state,settings,0).has("stop"),"captured target stops instead of silently retargeting second enemy")
 state.enemies[0].captured=false;state.enemies[0].hp=0
 check(Policy.decide(state,settings,0).has("stop"),"dead target stops instead of switching species")
 state.enemies[0].hp=100;state.ride_pet=1
 check(Policy.decide(state,settings,0).switch==0 or Policy.decide(state,settings,0).action=="defend","mounted pet excluded")
 state.pets[0].level=120
 check(Policy.decide(state,settings,0).has("stop"),"no suitable low-level pet pauses")
 state.ride_pet=-1;settings.capture_pet=0
 check(Policy.decide(state,settings,0).has("stop"),"explicit pet selection respects visible level cap")
 settings.capture_pet_max_level=120
 check(Policy.decide(state,settings,0).switch==0,"explicit higher level override honored")
 state.pets[0].pet_id="pet-1";state.pets[1].pet_id="pet-2";state.pets[2].pet_id="pet-3"
 settings.capture_pet_id="pet-2";settings.capture_pet=0;state.active_pet=-1
 check(Policy.decide(state,settings,0).switch==1,"stable selected identity overrides stale carried index")
 state.pets.remove_at(0)
 check(Policy.decide(state,settings,0).switch==0,"carried reorder retains exact chosen pet")
 state.pets.remove_at(0)
 check(Policy.decide(state,settings,0).has("stop"),"stored selected pet pauses rather than choosing another pet")
 settings.preset="train_pet"
 check(Policy.decide(state,settings,-1).action=="attack","pet training uses ordinary attacking policy")
 # Capture odds: a target no throw can catch yet is weakened first (斑尼迪克,
 # capture parameter -5, at full HP against a Lv120 player).
 var CaptureRules=load("res://server/capture_rules.gd")
 var player={"level":120,"speed":104,"charm":94,"luck":1}
 var gold={"hp":72,"max_hp":72,"level":1,"speed":9,"capture_parameter":-5,"can_capture":true}
 var full_odds=int(CaptureRules.evaluate(player,gold).winning_rolls)
 gold.hp=50
 var weak_odds=int(CaptureRules.evaluate(player,gold).winning_rolls)
 check(full_odds<Policy.MIN_CAPTURE_ODDS and weak_odds>=Policy.MIN_CAPTURE_ODDS,"斑尼迪克 cannot be caught at full HP (%d) but can at 50 HP (%d)"%[full_odds,weak_odds])
 var odds_state={"enemies":[{"hp":72,"max_hp":72,"level":1,"can_capture":true,"capture_odds":full_odds}],"pets":[{"hp":20,"level":1,"pet_id":"w"}],"active_pet":0,"ride_pet":-1}
 var odds_settings={"preset":"capture","capture_hp":100,"capture_pet":-1,"capture_pet_max_level":1}
 var odds_plan=Policy.decide(odds_state,odds_settings,0)
 check(odds_plan.action=="defend" and odds_plan.pet=="attack","odds below %d%%: the weaken pet attacks instead of throwing"%Policy.MIN_CAPTURE_ODDS)
 odds_state.enemies[0].capture_odds=weak_odds
 check(Policy.decide(odds_state,odds_settings,0).action=="capture","enough odds: capture")
 odds_state.enemies[0].erase("capture_odds")
 check(Policy.decide(odds_state,odds_settings,0).action=="capture","no odds reported (older state): capture as before")
 odds_state.enemies[0].capture_odds=0;odds_state.pets[0].level=5
 var stuck=Policy.decide(odds_state,odds_settings,0)
 check(stuck.has("stop") and str(stuck.stop).begins_with("捕获率为0"),"odds 0 and no weaken pet: stop with the reason, never throw forever")
 odds_state.enemies[0].capture_odds=5
 check(Policy.decide(odds_state,odds_settings,0).action=="capture","some odds and no weaken pet: keep throwing")
 print("BATTLE AUTO POLICY: %d failures"%failures)
 quit(1 if failures else 0)
