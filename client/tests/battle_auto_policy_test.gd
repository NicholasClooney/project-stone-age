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
 print("BATTLE AUTO POLICY: %d failures"%failures)
 quit(1 if failures else 0)
