extends "res://tests/yam_axe_ui_test.gd"
## Real production walking and portal transitions after a stated entrance fixture.
## Fixtures: level/prerequisites, combat stats, and two acquired materials.
## No interior location fixture or helper teleport is used after initial entry.
var host:Node
var walking_ms:int=0
var battle_ms:int=0
func original(script:String)->Dictionary:
 for npc in host.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))==script:return npc
 return {}
func rpc(command:Dictionary)->Dictionary:
 var result:=[{}];world.link.request(command,func(r):result[0]=r)
 if not await ready(func():return not result[0].is_empty(),"water route command settles"):return {}
 return result[0]
func path_to(target:Vector2i)->Array[Vector2i]:
 var queue:Array[Vector2i]=[world.cell];var parents:Dictionary={world.cell:world.cell};var cursor:=0
 var links:Dictionary=world.world_catalog.links(int(world.data.map_id))
 while cursor<queue.size() and not parents.has(target):
  var point:Vector2i=queue[cursor];cursor+=1
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next:Vector2i=point+offset
   if parents.has(next) or not world.is_walkable(next) or (links.has(next) and next!=target):continue
   parents[next]=point;queue.append(next)
 if not parents.has(target):return []
 var result:Array[Vector2i]=[target];var point:=target
 while point!=world.cell:point=parents[point];result.push_front(point)
 return result
func walk(target:Vector2i,portal:Dictionary={})->bool:
 var started:int=Time.get_ticks_msec()
 var points:Array[Vector2i]=path_to(target)
 if not check(not points.is_empty(),"cardinal original path exists map%d to%s"%[int(world.data.map_id),target]):return false
 points.pop_front()
 for point in points:
  world.walk_to(point)
  if point==target and not portal.is_empty():
   if not await ready(func():return int(world.data.map_id)==int(portal.to_map) and world.cell==Vector2i(int(portal.target[0]),int(portal.target[1])) and not world.area_transition_busy,"production source portal arrives"):return false
  elif not await ready(func():return world.cell==point and not world.moving,"production adjacent walking"):return false
 var settled:bool=check(await Wait.settle(self,world),"walk reports settled")
 walking_ms+=Time.get_ticks_msec()-started
 return settled
func walk_to_npc(npc:Dictionary)->bool:
 if not check(int(world.data.map_id)==int(npc.map_id),"NPC on naturally reached map"):return false
 var cell:=Vector2i(npc.cell[0],npc.cell[1])
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if not path_to(cell+offset).is_empty():return await walk(cell+offset)
 return check(false,"walkable source NPC adjacent cell")
func converse(script:String,confirm:String="yes")->bool:
 var npc:=original(script)
 if not await walk_to_npc(npc):return false
 var r:Dictionary=await rpc({"type":"quest_talk","npc_id":npc.id})
 if not check(r.get("ok",false) and r.has("dialogue"),"natural route source dialogue"):return false
 r=await rpc({"type":"quest_choose","token":r.dialogue.token,"choice":confirm})
 if r.has("dialogue"):r=await rpc({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"})
 if not check(r.get("ok",false),"natural route source commit"):return false
 return await ready(func():return not world.area_transition_busy and int(world.data.map_id)==int(host.automation.position_map),"source transition synchronizes")
func floor_to(map_id:int)->bool:
 var chosen:Dictionary={}
 for door in world.world_catalog.links(int(world.data.map_id)).values():
  if int(door.to_map)==map_id and not path_to(Vector2i(door.cell[0],door.cell[1])).is_empty():chosen=door;break
 if chosen.is_empty():print("NO PORTAL path map=",world.data.map_id," cell=",world.cell," host=",host.automation.position_cell," doors=",world.world_catalog.links(int(world.data.map_id)).values())
 if not check(not chosen.is_empty(),"reachable original portal to%d"%map_id):return false
 print("WATER WALK ",world.data.map_id," ",world.cell," -> ",chosen.cell," => ",chosen.to_map," ",chosen.target)
 return await walk(Vector2i(chosen.cell[0],chosen.cell[1]),chosen)
func guard(script:String)->bool:
 if not await converse(script):return false
 if not await ready(func():return host.battle_open and world.battle_view.visible,"natural guard opened"):return false
 var started:int=Time.get_ticks_msec()
 for i in range(100):
  var state:Dictionary=host.battle.snapshot()
  if not state.active:break
  var target:=0
  for j in range(state.enemies.size()):
   if int(state.enemies[j].hp)>0:target=j;break
  await rpc({"type":"battle_command","action":"attack","target":target})
 var closed:Dictionary=await rpc({"type":"battle_close"})
 battle_ms+=Time.get_ticks_msec()-started
 print("GUARD CLOSE ",script," result=",closed," host=",host.automation.position_map,"/",host.automation.position_cell," view=",world.cell)
 if not check(closed.get("outcome","")=="win","actual guard outcome must be victory"):return false
 return await ready(func():return not world.battle_view.visible and not world.area_transition_busy and world.cell==host.automation.position_cell,"original guard victory Warp settles")
func to_sage()->bool:
 if not await converse("genout/wpm_200_73_696"):return false
 for map_id in range(21202,21209):
  if not await floor_to(map_id):return false
 if not await guard("200/sb_mzl.arg"):return false
 for map_id in range(21209,21215):
  if not await floor_to(map_id):return false
 if not await guard("200/sb_mzn.arg"):return false
 if not check(int(world.data.map_id)==21215,"two real guard victories reach goddess floor"):return false
 if not await floor_to(21315):return false
 for map_id in range(21314,21307,-1):
  if not await floor_to(map_id):return false
 if not await converse("genout/wpm_21308_20_10"):return false
 if not await walk_to_npc(original("jaruga/event/hekisei03")):return false
 return true

func return_to_goddess()->bool:
 var exit_door:Dictionary=world.world_catalog.links(21308).get(Vector2i(20,8),{})
 if not check(not exit_door.is_empty(),"original sage return portal exists"):return false
 if not await walk(Vector2i(20,8),exit_door):return false
 for map_id in range(21309,21316):
  if not await floor_to(map_id):return false
 if not await floor_to(21215):return false
 if not await walk_to_npc(original("jaruga/event/hekisei01")):return false
 print("WATER NATURAL ROUTE: original gates/two real fights/material door/sage return completed; final reward uses phone click")
 return true
