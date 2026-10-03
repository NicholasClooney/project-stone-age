extends "res://tests/yam_axe_ui_test.gd"
const JewelHelper=preload("res://server/four_jewels_helper.gd")
const SCHOLAR="extra/event/hougyoku@6000:58:44"
func jewel_battle(host,part:Dictionary) -> bool:
 world.quest_helper_menu.open_menu()
 if not await click(visit_button("jewels:hunt:%d"%int(part.item),"near",31)):return false
 if not await ready(func():return not world.quest_helper_travel.active,"Real pointer hunt navigation completes"):return false
 if not check(await Wait.settle(self,world),"Hunt movement settles"):return false
 var map_id:int=host.automation.position_map
 var cell:Vector2i=host.automation.position_cell
 var rng:=RandomNumberGenerator.new()
 var found:=false
 # Select a legal one-enemy original roll, never replace an enemy or its drop.
 for seed_value in range(30000):
  rng.seed=seed_value
  var roll:Dictionary=host.encounter_catalog.roll(map_id,cell,rng,host.session.snapshot().original_items)
  if int(roll.get("group_id",-1))!=int(part.group) or roll.enemies.size()!=1:continue
  if int(roll.enemies[0].source_enemy_id)!=int(part.enemy) or not int(part.item) in roll.enemies[0].generated_drops:continue
  host.encounter_rng.seed=seed_value;found=true;break
 if not check(found,"Original RNG supplies one source enemy and source jewel"):return false
 if not check(host.wild_encounter(map_id,cell).ok,"Real Backend admits original encounter"):return false
 if not await ready(func():return world.battle_view.visible and not world.battle_view.is_animating(),"Real remote battle is rendered"):return false
 await proof("jewels-battle-%s"%part.name)
 for turn in range(10):
  if not host.battle.snapshot().active:break
  if not await ready(func():return not world.battle_view.is_animating(),"Battle animation finishes before input"):return false
  if not await click(world.battle_view.commands[0]):return false
  if not await click(world.battle_view.target_buttons[1]):return false
  if not check(await Wait.settle(self,world),"Real attack click resolves over socket"):return false
  if not await ready(func():return not world.battle_view.is_animating(),"Attack animation fully rendered"):return false
 if not check(host.battle.snapshot().get("outcome")=="win","Real clicked attacks win source encounter"):return false
 if not await ready(func():return world.battle_view.return_button.visible,"Actual battle return button ready"):return false
 if not await click(world.battle_view.return_button):return false
 if not await ready(func():return not world.battle_view.visible,"Real return click closes battle"):return false
 if not check(await Wait.settle(self,world) and int(part.item) in world.session.snapshot().original_items,"Earned jewel visible in remote profile"):return false
 return true
func run() -> void:
 root.unfocusable=true
 root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 proof_dir=OS.get_environment("STONE_AGE_PROOF_DIR")
 if not proof_dir.is_empty():DirAccess.make_dir_recursive_absolute(proof_dir)
 var host=Backend.new();root.add_child(host)
 host.session._profile.no_random_encounters=true
 host.session._profile.default_companions_claimed=true
 host.session.gm_raise_level(-1,60)
 for stat in ["vitality","strength","toughness","dexterity"]:host.session.gm_set_base_stat(-1,stat,500)
 host.session.gm_heal(-1)
 for key in host.session._profile.inventory:host.session._profile.inventory[key]=0
 var server=preload("res://server/ws_server.gd").new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Portrait source server on port0"):return
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://jewels-ui.cfg";root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and world.link.online,"Remote portrait startup"):return
 if not check(await Wait.settle(self,world) and world.backend==null,"Remote UI lacks backend"):return
 if not await stage("jewels:request",31):return
 await proof("jewels-01-original-scholar")
 if not await choose("yes") or not await choose("ok"):return
 for part in JewelHelper.PARTS:
  if not await jewel_battle(host,part):return
 if not await stage("jewels:return",31):return
 await proof("jewels-02-original-five-items")
 if not await choose("yes"):return
 await proof("jewels-03-original-bracelet-reward")
 if not await choose("ok"):return
 if not check(Rules.flag(world.session.snapshot(),"ended",45) and world.session.snapshot().original_items==[2765],"Clicked final reply commits source bracelet and45"):return
 world.show_adventure_menu("inventory")
 if not await click(world.adventure_menu.panel.get_node("OriginalItemSlot_0")):return
 var description:Label=world.adventure_menu.panel.find_child("OriginalEffectsMetadata",true,false)
 if not check(is_instance_valid(description) and description.text.contains("未生效"),"Revival guardian is labelled inactive"):return
 await proof("jewels-04-source-bracelet-detail")
 if not await scroll_details():return
 await proof("jewels-05-visible-effect-label")
 if not await click(world.adventure_menu.panel.get_node("EquipOriginalItem")):return
 if not check(await Wait.settle(self,world) and int(world.session.snapshot().original_equipment.bracelet)>0,"Real equip click commits original bracelet slot"):return
 world.close_adventure_menu()
 if not await stage("jewels:return",31):return
 if not check(int(world.data.map_id)==4000 and host.original_quests.npc_by_id(SCHOLAR).cell==[53,101],"Real helper click finds scholar at original first relocated point"):return
 await proof("jewels-06-personal-scholar-moved")
 # This last visit deliberately leaves the relocated scholar's dialogue open.
 # Finish its protocol while the socket is live, before freeing the world.
 world.world_travel.quest_dialogue.close()
 if not check(await Wait.settle(self,world),"Final scholar dialogue closes before socket teardown"):return
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();host.queue_free();await process_frame
 print("FOUR JEWELS UI: %d failures"%failures)
 quit(1 if failures else 0)
