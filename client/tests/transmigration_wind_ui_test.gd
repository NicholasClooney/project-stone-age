extends "res://tests/support/transmigration_wind_route.gd"
const Clock=preload("res://scripts/clock.gd")
## Same entire natural route, with real NPC/choice mouse input at phone width.
var shot_serial:=0
func run()->void:
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 await super.run()
func use(npc:Dictionary,keyword:String="")->bool:
 print("WIND click ",npc.get("id","")," map=",world.data.map_id," cell=",world.cell)
 if not check(await approach(npc),"Natural walk reaches actual NPC click"):return false
 var ui_started:int=Clock.ticks_msec()
 var entries:Array=world.world_travel.entries
 var matches:Array=entries.filter(func(n):return str(n.id)==str(npc.id))
 if not check(matches.size()==1,"Actual source NPC rendered exactly once"):return false
 var sprite=world.world_travel.sprites[entries.find(matches[0])]
 if not check(sprite.texture!=null,"Original NPC texture exists"):return false
 # Accelerated walking must settle the actual camera before pixel hit testing.
 world.camera.reset_smoothing();world.camera.force_update_scroll()
 await process_frame
 var point:Vector2=sprite.get_global_transform_with_canvas()*sprite.get_rect().get_center()
 print("WIND click screen ",point," paused=",world.paused_input)
 if str(npc.source_script)=="100/sb_kbu.arg":await proof("390-wind-guard-before-click")
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true)
 var d=world.world_travel.quest_dialogue
 if not await ready(func():return d.active and not d.busy,"Actual NPC click opens server dialogue"):
  print("WIND click failed message=",world.message.text," pending=",host.original_quests.pending)
  await proof("390-wind-click-failed")
  quit(1);return false
 var phase:String=host.original_quests.pending.get("phase","")
 if str(npc.source_script) in ["sainasu/event/genou_1","sainasu/event/genou_4","sainasu/event/event12","genout/wpm_100_443_127","100/sb_kgi.arg"]:
  shot_serial+=1;await proof("390-wind-%02d-%s"%[shot_serial,str(npc.source_script).get_file().replace(".","-")])
 if is_instance_valid(d.service_controls) and d.service_controls.get_script()==preload("res://scripts/quest_pet_selection_controls.gd"):
  await proof("390-wind-temple-offering-note")
  var candidate:Dictionary=d.service_controls.candidates.filter(func(p):return int(p.level)==60)[0]
  if not await click(d.service_controls.get_node("QuestPet_"+str(candidate.pet_id))):return false
  await proof("390-wind-temple-offering-selected")
  if not await click(d.service_controls.confirm):return false
  if not await Wait.settle(self,world):return false
 elif phase=="KEYWORD":
  if not await click(d.service_controls.answer):return false
  for character in keyword:
   var key:=InputEventKey.new();key.pressed=true;key.unicode=character.unicode_at(0);root.push_input(key,true)
  if not await choose("submit"):return false
 else:
  if not await choose("yes"):return false
 if is_instance_valid(d) and d.active:
  if not await choose("ok"):return false
 timing_ui+=Clock.ticks_msec()-ui_started
 if host.battle_open:
  var battle_started:int=Clock.ticks_msec()
  for turn in range(100):
   var state:Dictionary=host.battle.snapshot()
   if not state.active:break
   var target:=0
   for index in range(state.enemies.size()):
    if int(state.enemies[index].hp)>0:target=index;break
   host.handle({"type":"battle_command","action":"attack","target":target})
  if not check(host.handle({"type":"battle_close"}).ok,"Naturally clicked source battle settles"):return false
  if not await ready(func():return not world.battle_view.visible,"Actual remote battle view closes"):return false
  timing_battle+=Clock.ticks_msec()-battle_started
 return await Wait.settle(self,world)

func after_completion()->bool:
 # Carried-pet ingredients are isolated transaction fixtures, not a claim of
 # naturally capturing/training two level60/61 pets in this UI route test.
 host.session.gm_grant_pet(95);host.session.gm_raise_level(host.session._profile.pets.size()-1,61)
 host.session.gm_grant_pet(95);host.session.gm_raise_level(host.session._profile.pets.size()-1,60)
 host.publish();await Wait.settle(self,world)
 if not await use(find_npc("sainasu/event/genou_2")):return false
 if not check(host.session.snapshot().pets.size()==1 and int(host.session.snapshot().pets[0].level)==61,"Actual temple click consumes chosen60 and preserves61"):return false
 world.quest_helper_menu.open_menu()
 await proof("390-wind-completed-helper")
 world.quest_helper_menu.close_menu()
 return true
