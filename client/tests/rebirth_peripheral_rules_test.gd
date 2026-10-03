extends SceneTree
const Loyalty=preload("res://server/loyalty.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Spirits=preload("res://server/spirits.gd")
const Rules=preload("res://server/rebirth_equipment_rules.gd")
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1
func run()->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/rebirth_peripheral_source.json"))
 var same:bool=true;var capture:bool=true;var defaults:bool=true
 for row in fixture.loyalty:
  var result:int=Loyalty.value(row[0],row[1],row[2],row[3],row[4],row[5])
  if result!=int(row[6]):same=false;push_error("C loyalty mismatch "+str(row))
  if Loyalty.capture_variable(row[0],row[1],row[2],row[3],row[5])!=int(row[7]):capture=false
  if int(row[5])==0 and result!=Loyalty.value(row[0],row[1],row[2],row[3],row[4]):defaults=false
 check(same,"1800 independent C oracle loyalty cases including negative variable and future >140 division")
 check(capture,"capture initialization preserves original compliance then excess-debt order")
 check(defaults,"omitted owner count exactly preserves all zero-transmigration outcomes")
 check(Loyalty.value(1,60,120,300,-4000,1)==29,"negative earned loyalty gets69 before final low clamp")
 check(Loyalty.value(1,60,1,100,0,1)==Loyalty.value(1,60,1,100,0,5),"bonus is not multiplied by owner count")
 var earned:int=Loyalty.capture_variable(1,60,1,100,1)
 check(earned==-4000 and Loyalty.value(1,60,1,100,earned,1)==95,"source capped capture debt and later recomputation are distinct from temporary60")
 for count in [0,1,5]:
  var pet:Dictionary={"pet_id":"pet-17","level":120,"modai":300,"variable_ai":-4000,"xp":987,"skills":[1,2],"loyalty":0}
  var before:Dictionary=pet.duplicate(true);Loyalty.refresh(pet,{"level":1,"charm":60},count)
  var shown:int=pet.loyalty;pet.loyalty=before.loyalty
  check(pet==before and shown==Loyalty.value(1,60,120,300,-4000,count),"refresh changes only derived loyalty count"+str(count))
 var codes:Array=["","level","strength","dexterity","transmigration"]
 same=true
 for row in fixture.equipment_rules:
  var definition:Dictionary={"level":row[4],"need_strength":row[5],"need_dexterity":row[6],"need_transmigration":row[7]}
  if Rules.requirement_error(row[0],row[1],row[2],row[3],definition)!=codes[int(row[8])]:same=false
  var owner:Dictionary={"level":row[0],"transmigration":row[1],"base_stats":{"strength":row[2],"dexterity":row[3]}}
  if Equipment.definition_error(owner,definition)!=("" if int(row[8])==0 else Spirits.TOO_WEAK):same=false
 check(same,"384 C requirement cases: rebirth skips only level, raw STR/DEX/TRANS still gate")
 var ids:Array=[];same=true
 for row in fixture.equipment:
  ids.append(int(row.id))
  if not Equipment.ITEMS.has(int(row.id)) or int(Equipment.ITEMS[int(row.id)].level)!=int(row.level):same=false
  if int(row.need_strength)!=0 or int(row.need_dexterity)!=0 or int(row.need_transmigration)!=0:same=false
 var actual:Array=Equipment.ITEMS.keys();ids.sort();actual.sort()
 check(same and ids==actual,"all166 supported equipment IDs match source level and all three zero requirement columns")
 var legacy_ids:Array=[];var legacy_actual:Array=[];same=true
 for row in fixture.legacy_equipment:
  legacy_ids.append(int(row.id))
  var found:bool=false
  for data in Spirits.ITEMS.values():
   if int(data.item_id)==int(row.id):found=true;same=same and int(data.level)==int(row.level)
  same=same and found and int(row.need_strength)==0 and int(row.need_dexterity)==0 and int(row.need_transmigration)==0
 for data in Spirits.ITEMS.values():legacy_actual.append(int(data.item_id))
 legacy_ids.sort();legacy_actual.sort()
 check(same and legacy_ids==legacy_actual,"all5 counted legacy definitions match source level and zero requirement columns")
 same=true
 for id in Equipment.ITEMS:
  for count in [0,1,5,33]:
   for level in [1,80]:
    var owner:Dictionary={"level":level,"transmigration":count}
    if Equipment.equip_error(owner,id).is_empty()!=(count>0 or level>=int(Equipment.ITEMS[id].level)):same=false
 check(same,"all166 public equip checks preserve zero-count levels and positive-count exemption")
 print("REBIRTH PERIPHERAL RULES: %d failures"%failures);quit(1 if failures else 0)
