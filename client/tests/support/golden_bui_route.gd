extends RefCounted
## Original service/portal fixture. Tickets are source-item inputs, never route grants.
const Guide=preload("res://server/golden_bui_helper.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
static func choose(b,r:Dictionary,choice:String,text:String="")->Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":choice,"text":text})
static func enter(b,base:int,lobby:int=-1)->bool:
 if lobby<0:lobby=851 if base==840 else 811
 var x:=29 if lobby==851 else (30 if base==800 else 28)
 var id:="genout/wpm_%d_%d_20@%d:%d:20"%[lobby,x,lobby,x]
 var ticket:=2755 if base==800 else (2756 if base==820 else 2757)
 if ticket not in b.session._profile.original_items:Equipment.add(b.session._profile,ticket)
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 b.automation.position_changed(lobby,Vector2i(x,22),true)
 var result:=choose(b,b.handle({"type":"quest_talk","npc_id":id}),"yes")
 return result.get("ok",false) and b.automation.position_map==base and b.quest_arrival.has_arrival(b,base,b.automation.position_cell)
static func challenge(b)->bool:
 var actor:Dictionary={}
 for npc in b.quest_catalog.active_npcs():
  if int(npc.map_id)==b.automation.position_map and str(npc.get("kind","")) in ["golden_bui_quiz","golden_bui_janken"]:actor=npc;break
 if actor.is_empty() or not Travel.walk_near(b,actor,[int(actor.map_id)]):return false
 if str(actor.kind)=="golden_bui_quiz" and 2752 not in b.session._profile.original_items:Equipment.add(b.session._profile,2752)
 var result:=choose(b,b.handle({"type":"quest_talk","npc_id":actor.id}),"yes")
 for index in range(12):
  if not result.get("ok",false):return false
  if result.get("closed",false):return b.automation.position_map==int(actor.map_id) and b.automation.position_cell.y<18
  var state:Dictionary=b.original_quests.pending.get("service_state",{})
  if str(actor.kind)=="golden_bui_quiz":result=choose(b,result,"submit" if int(state.get("answer_type",0))==4 else str(state.get("answer_choice","")),str(state.get("answer_text","")))
  else:
   # Select a deterministic source RNG outcome; execute the actual service
   # result and saved Warp. Never write position, flags or arrival after it.
   var rng:=RandomNumberGenerator.new()
   for value in range(100):
    rng.seed=value
    if rng.randi_range(0,2)==1:b.original_quests.services.rng.seed=value;break
   result=choose(b,result,"rock")
 return false
static func reach_floor(b,map_id:int)->bool:
 var base:=Guide.floor_base(map_id)
 if map_id==810:base=820 if Guide.floor_base(b.automation.position_map)==820 or int(b.session._profile.player.level) in range(50,70) else 800
 if map_id==850:base=840
 if base<0:return false
 var current:int=b.automation.position_map
 var reached:bool=b.quest_arrival.has_arrival(b,current,b.automation.position_cell)
 var wrong_side:bool=current==map_id and Guide.floor_base(map_id)>=0 and b.automation.position_cell.y<18
 if not reached or (Guide.floor_base(current)!=base and current!=map_id) or current>map_id or wrong_side:
  if not enter(b,base):return false
 for step in range(11):
  current=b.automation.position_map
  if current==map_id:return true
  if Guide.floor_base(current)!=base:return false
  if b.automation.position_cell.y>=18 and not challenge(b):return false
  var next:int=(850 if base==840 else 810) if current==base+9 else current+1
  var crossed:=false
  for portal in b.quest_helper.places.links(current).values():
   if int(portal.to_map)!=next or portal.get("disabled",false) or portal.has("gate_source"):continue
   if not Route.walk(b,current,Vector2i(int(portal.cell[0]),int(portal.cell[1])),[current]).get("ok",false):continue
   if not b.handle({"type":"report_position","map_id":next,"cell":portal.target}).get("ok",false):return false
   crossed=true;break
  if not crossed:return false
 return false
static func near(b,npc:Dictionary)->bool:
 if npc.is_empty():return false
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 if Guide.protected_map(int(npc.map_id)):
  if not reach_floor(b,int(npc.map_id)):return false
  return Travel.walk_near(b,npc,[int(npc.map_id)])
 b.automation.position_changed(int(npc.map_id),Vector2i(16,13) if int(npc.map_id) in [2020,4020] else Vector2i(int(npc.cell[0]),22),true)
 return true
