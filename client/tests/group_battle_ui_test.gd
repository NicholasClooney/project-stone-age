extends SceneTree
const Battle = preload("res://server/battle_session.gd")
var failures := 0
var view
var authority
func _initialize(): call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok: failures+=1
func settle():
 while view.elapsed<view.feedback_until+0.01:
  view._process(1.0/60.0)
  view.battle_effects._process(1.0/60.0)
func pet(id: int) -> Dictionary:
 return {"name":"伙伴%d" % id,"species":"wooli","sprite":100250+id,"hp":120,"max_hp":120,"attack":4,"speed":10,"defence":2,"learned_skills":[3,10,50]}
func foe(id: int) -> Dictionary:
 return {"name":["乌力","乌力乌力","乌力斯坦"][id],"species":"wooli","sprite":100250+id,"hp":100,"max_hp":100,"attack":2,"speed":1,"defence":1}
func start(roster_count: int = 2, enemy_count: int = 3):
 authority=Battle.new()
 var roster: Array = []
 for i in range(roster_count):
  var companion=pet(i%3)
  companion.name="伙伴%d"%i
  roster.append(companion)
 var enemies: Array = []
 for i in range(enemy_count): enemies.append(foe(i%3))
 var initial=authority.start_battle({"player_hp":500,"player_max_hp":500,"player_attack":5,"player_speed":30,"enemies":enemies,"pets":roster,"active_pet":0,"capture_slots":3})
 view.open_battle(initial)
 settle()
func submit(action: String):
 authority.set_pet_target(view.pet_target)
 view.show_state(authority.submit_action(action,view.player_target,view.switch_pet_index))
func choose_pet(command: String):
 if command=="skill": authority.set_pet_skill(view.selected_pet_skill)
 authority.set_pet_command(command)
func picture(name: String):
 if DisplayServer.get_name()=="headless": return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://../artifacts/"+name+".png")
func run():
 view=load("res://scripts/battle_view.gd").new()
 root.add_child(view)
 await process_frame
 view.set_process(false)
 view.battle_effects.set_process(false)
 view.action_requested.connect(submit)
 view.pet_command_requested.connect(choose_pet)
 start()
 check(view.actors.size()==5,"three foes and companion occupy stable actor slots")
 for index in [0,1,2,3,4]: check(view.hp_bars[index].visible,"all five original overhead HP bars visible")
 check(view.actors[3].home-view.actors[1].home==Vector2(-32,24),"native enemy slot reorder and spacing")
 await picture("battle-three-enemies")
 view.target_buttons[3].pressed.emit()
 settle()
 check(view.player_target==1 and view.command_phase=="pet","second foe click queues player target and opens pet choices")
 view.target_buttons[4].pressed.emit()
 var result=authority.snapshot()
 check(view.pet_target==2 and result.turn==1,"pet independently targets third enemy")
 check(result.turn_frames.any(func(frame): return frame.actor=="player" and frame.target_index==1),"player frame retains clicked target")
 check(result.turn_frames.any(func(frame): return frame.actor=="pet" and frame.target_index==2),"pet frame retains independent target")
 settle()
 for i in [0,1,2,3,4]: check(view.displayed_hp[i]==view.health_of(result,i),"animated HP settles to authority for slot%d"%i)
 view._request_action("pet")
 var choices=[]
 for node in view.choice_panel.get_children():
  if node is Button: choices.append(node)
 check(choices.size()==2 and choices[0].disabled and not choices[1].disabled and view.choice_panel.has_node("WithdrawPet"),"original roster offers another live companion and withdrawal")
 await picture("battle-pet-roster")
 choices[1].pressed.emit()
 settle()
 check(authority.snapshot().active_pet==1 and view.actors[2].enabled,"pet switch consumes a round and replacement enters")
 check(view.actors[2].animations==view.manifest.characters["100251"],"replacement uses its own original animation set")
 view._request_action("pet")
 view.choice_panel.get_node("WithdrawPet").pressed.emit()
 settle()
 check(authority.snapshot().active_pet==-1 and not view.actors[2].sprite.visible and not view.hp_bars[2].visible,"withdraw hides companion and overhead bar")
 view._request_action("pet")
 for node in view.choice_panel.get_children():
  if node is Button and not node.disabled and node.text.begins_with("伙伴0"):
   node.pressed.emit()
   break
 settle()
 check(authority.snapshot().active_pet==0 and view.actors[2].sprite.visible,"withdrawn companion can return through same roster")
 view._request_action("defend")
 settle()
 view.show_learned_skills()
 var skill_choices=[]
 for node in view.choice_panel.get_children():
  if node is Button: skill_choices.append(node)
 check(skill_choices.size()==3,"trained original skills appear in pet skill picker")
 skill_choices[1].pressed.emit()
 view.select_target(4)
 check(authority.snapshot().turn_frames.filter(func(frame):return frame.actor=="pet" and frame.skill_id==10 and not str(frame.outcome).begins_with("counter")).size()==2,"continuous attack creates two authoritative impact animations")
 settle()
 # Source effects use actual flags, never arbitrary visual randomness.
 view.battle_effects.reset()
 view.battle_effects.impact(Vector2(300,300),12,false,true)
 check(view.battle_effects.active.filter(func(effect):return effect.kind=="critical").size()==5,"critical hit uses five original stars")
 view.battle_effects.word(Vector2(400,300),26504)
 view.battle_effects.word(Vector2(500,300),26507)
 await picture("battle-critical-miss-counter")
 start()
 # Capture one weakened target while the two remaining foes continue.
 authority._state.enemies[1].hp=30
 authority.set_pet_command("defend")
 view.pending_action="capture"
 # Reference capture is a roll; a maximal bonus keeps these layout checks off the RNG.
 authority._config.capture_bonus=100
 view.show_state(authority.submit_action("capture",1))
 check(view.state.active and view.actors[3].hide_at<INF,"capturing one target keeps battle active and schedules correct actor removal")
 settle()
 check(not view.actors[3].sprite.visible and view.actors[1].sprite.visible and view.actors[4].sprite.visible,"only captured opponent leaves formation")
 view.pending_action="defend"
 view.show_state(authority.submit_action("defend",0))
 settle()
 check(not view.actors[3].sprite.visible,"captured enemy remains absent on following turns")
 start(5)
 view._request_action("pet")
 check(view.choice_panel.get_node("PreviousPetPage").disabled,"five-pet roster begins at first native three-row page")
 view.choice_panel.get_node("NextPetPage").pressed.emit()
 check(view.choice_panel.has_node("RosterPet4") and view.choice_panel.get_node("NextPetPage").disabled,"second roster page exposes fifth pet without overlapping rows")
 await picture("battle-pet-roster-page2")
 view.choice_panel.get_node("RosterPet4").pressed.emit()
 settle()
 check(authority.snapshot().active_pet==4,"fifth roster companion switches through original menu")
 for i in range(3): start()
 check(view.actors.size()==5,"reopening grouped encounters does not accumulate actor nodes")
 start(2,10)
 check(view.can_render_troop(authority.snapshot().enemies),"ten mixed foes have verified original animation resources")
 check(not view.can_render_troop([{"sprite":100298}]) and not view.can_render_troop([]),"unavailable original sprite and empty encounters are rejected without substitutes")
 check(view.actors.size()==12,"ten enemies and player/pet retain twelve stable actor slots")
 var expected=[Vector2(101,150),Vector2(69,174),Vector2(133,126),Vector2(37,198),Vector2(165,102),Vector2(197,202),Vector2(133,250),Vector2(261,154),Vector2(69,298),Vector2(325,106)]
 for i in range(10):
  var actor=int(view.enemy_actor(i))
  check(view.hp_bars[actor].position==view.actors[actor].point+Vector2(0,-80),"enemy%d retains OG fixed HP anchor even for small sprites"%i)
  check(view.actors[actor].home==expected[i],"enemy%d uses native row placement"%i)
  check(view.hp_bars[actor].visible and view.displayed_hp[actor]==100,"enemy%d has independent original health bar"%i)
  check(view.actors[actor].character_id==str(100250+i%3),"enemy%d keeps its own mixed-species art"%i)
 await picture("battle-ten-mixed-enemies")
 view.target_buttons[view.enemy_actor(9)].pressed.emit()
 settle()
 view.target_buttons[view.enemy_actor(8)].pressed.emit()
 var ten_result=authority.snapshot()
 check(view.player_target==9 and view.pet_target==8,"player and pet independently select second-row targets")
 settle()
 for i in range(12):check(view.displayed_hp[i]==view.health_of(ten_result,i),"ten-foe animation HP settles for actor%d"%i)
 check(ten_result.turn_frames.any(func(frame):return frame.actor=="enemy" and frame.enemy_index==9),"last enemy attacks with its own animation slot")
 authority._state.enemies[9].hp=1
 authority.set_pet_command("defend")
 view.pending_action="capture"
 authority._config.capture_bonus=100
 view.show_state(authority.submit_action("capture",9))
 settle()
 check(not view.actors[view.enemy_actor(9)].sprite.visible and view.actors[view.enemy_actor(8)].sprite.visible,"capturing tenth enemy removes only its original formation slot")
 await picture("battle-ten-after-capture")
 start()
 check(view.actors.size()==5 and not view.hp_bars[11].visible,"returning to small troop hides unused large-formation health bars")
 view.queue_free()
 await process_frame
 print("GROUP BATTLE UI: %d failures"%failures)
 quit(1 if failures else 0)
