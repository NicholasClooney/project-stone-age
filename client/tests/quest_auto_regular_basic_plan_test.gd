extends SceneTree
## Selection-only unit fixtures. No route, source binding or transaction proof.
const Rules=preload("res://server/original_quests.gd")
const Saton=preload("res://server/quest_auto_saton_plan.gd")
const Doctor=preload("res://server/quest_auto_doctor_plan.gd")
const Harn=preload("res://server/quest_auto_harn_plan.gd")
var failures:=0
var assertions:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:
  failures+=1
  push_error(label)
func fixture(items:Array=[],now:Array=[],ended:Array=[],level:int=80)->Dictionary:
 var p:Dictionary={"player":{"level":level},"original_items":items.duplicate(),
  "original_events":{"now":[0,0,0,0,0,0],"ended":[0,0,0,0,0,0]},"pets":[]}
 for event in now:Rules.set_flag(p,"now",event,true)
 for event in ended:Rules.set_flag(p,"ended",event,true)
 return {"session":{"_profile":p}}
func expect(plan,b:Dictionary,job:int,stage:String,key:String="",line:int=0)->Dictionary:
 var before:Dictionary=b.duplicate(true)
 var result:Dictionary=plan.select(b,job)
 check(b==before,"read-only: "+stage)
 check(result.status==("done" if stage=="done" else "manual"),"status: "+stage)
 check(not result.has("step") and not result.has("action"),"unfrozen stage cannot execute: "+stage)
 if stage=="done":
  check(result=={"status":"done"},"done is terminal")
 else:
  check(result.get("stage")==stage,"stage: "+stage)
  check(not str(result.get("reason","")).is_empty(),"explain manual boundary: "+stage)
  if not key.is_empty():
   check(result.required_source.key==key,"precise source key: "+stage)
   check(result.required_source.line==line,"precise original branch line: "+stage)
 return result
func _initialize()->void:call_deferred("run")
func run()->void:
 # Saton: three treasures, no reset branch, human boss decision.
 const SATON="sainasu/event/event13_1"
 expect(Saton,fixture([],[],[],15),10,"level")
 expect(Saton,fixture([],[],[],16),10,"request",SATON,28)
 expect(Saton,fixture([],[13]),10,"replace_footprint",SATON,20)
 expect(Saton,fixture([2431],[13]),10,"wait_boss","100/sb_nusu1.arg")
 expect(Saton,fixture([2431,2428],[13]),10,"wait_boss","100/sb_nusu2.arg")
 expect(Saton,fixture([2431,2428,2429],[13]),10,"wait_boss","100/sb_nusu3.arg")
 expect(Saton,fixture([2428,2429,2430],[13]),10,"return_treasures",SATON,9)
 expect(Saton,fixture([],[],[13]),10,"done")
 expect(Saton,fixture([],[],[14]),10,"request",SATON,28)
 # Doctor: neither one nor multiple pets permits implicit UID consumption.
 const DOCTOR="sainasu/event/event15_1"
 expect(Doctor,fixture([],[],[],9),6,"level")
 expect(Doctor,fixture([],[],[],10),6,"request",DOCTOR,26)
 expect(Doctor,fixture([],[15]),6,"manual_uid",DOCTOR,4)
 for count in [1,2]:
  var b=fixture([],[15])
  for index in range(count):b.session._profile.pets.append({"uid":"pet-%d"%index,"level":50,"template_id":74})
  expect(Doctor,b,6,"manual_uid",DOCTOR,4)
 expect(Doctor,fixture(),7,"prerequisite")
 expect(Doctor,fixture([],[],[15],15),7,"level")
 expect(Doctor,fixture([],[],[15],16),7,"request",DOCTOR,37)
 expect(Doctor,fixture([],[16],[15]),7,"manual_uid",DOCTOR,15)
 expect(Doctor,fixture([],[],[15]),6,"done")
 expect(Doctor,fixture([],[],[16]),7,"done")
 # Harn scope is a coordinator decision: NOW18 is allowed, END18 followup is not.
 const HARN="jaruga/event/20501ev1"
 const COMMISSION="jaruga/event/20501ev3"
 expect(Harn,fixture(),19,"unsupported_job")
 expect(Harn,fixture([],[],[],14),22,"level")
 expect(Harn,fixture([],[],[],15),22,"commission",COMMISSION,50)
 expect(Harn,fixture([],[18]),22,"replace_commission",COMMISSION,42)
 expect(Harn,fixture([],[],[18]),22,"commission_unavailable")
 expect(Harn,fixture([2467]),22,"commission_unavailable")
 expect(Harn,fixture([2466],[18]),22,"request_axe",HARN,40)
 expect(Harn,fixture([2466],[18,19]),22,"replace_pot",HARN,26)
 expect(Harn,fixture([2466,2463],[18,19]),22,"fill_water","jaruga/event/20501ev2",15)
 expect(Harn,fixture([2466,2464],[18,19]),22,"claim_axe",HARN,15)
 expect(Harn,fixture([2466,2464,2463],[18,19]),22,"claim_axe",HARN,15)
 expect(Harn,fixture([],[],[19]),22,"missing_axe")
 expect(Harn,fixture([2465]),22,"inconsistent_axe")
 expect(Harn,fixture([2465],[18],[19]),22,"done")
 expect(Harn,fixture([2465],[],[18,19]),22,"done")
 for plan in [Saton,Doctor,Harn]:
  for other_job in [34,35,999]:expect(plan,fixture(),other_job,"unsupported_job")
 print("quest_auto_regular_basic_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
