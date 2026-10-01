extends RefCounted
## gmsv/npc/npc_charm.c: CHAR_CHARM and CHAR_GOLD are base fields.
const Equipment=preload("res://server/original_equipment.gd")

static func cost(profile: Dictionary) -> int:
 var player: Dictionary=profile.player
 if not Equipment.integer(player.get("level"),1,1000000) or not Equipment.integer(player.get("charm"),0,100) or not Equipment.integer(player.get("gold"),0,1000000000) or not Equipment.integer(player.get("transmigration",0),0,2147483647):return -2
 var charm:=int(player.charm)
 if charm>=100:return -1
 if charm<=1:charm=3
 @warning_ignore("integer_division")
 var amount:=int(player.level)*10*(charm/3)*(int(player.get("transmigration",0))+1)
 return amount if amount<=2147483647 else -2

static func talk(owner, backend, npc: Dictionary) -> Dictionary:
 if cost(backend.session.snapshot()) == -2:return {"ok":false,"reason":"美容参数无效。"}
 var reply: Dictionary=owner.window(npc,{},"charm_start",str(npc.dialogue.start),false)
 reply.dialogue.choices=npc.dialogue.choices.duplicate(true)
 return reply

static func choose(owner, backend, current: Dictionary, choice: String) -> Dictionary:
 var npc: Dictionary=current.npc
 var phase: String=current.phase
 if phase=="charm_start":
  if choice=="leave":return {"ok":true,"closed":true}
  if choice!="charm":return {"ok":false,"reason":"无效选择。"}
 elif phase=="charm_confirm":
  if choice=="no":return {"ok":true,"closed":true}
  if choice!="yes":return {"ok":false,"reason":"无效选择。"}
 else:return {"ok":false,"reason":"无效美容对话。"}
 var profile: Dictionary=backend.session.snapshot()
 var amount:=cost(profile)
 if amount==-2:return {"ok":false,"reason":"美容参数无效。"}
 if amount==-1:return owner.window(npc,{},"end",str(npc.dialogue.full),false)
 if phase=="charm_start":return owner.window(npc,{},"charm_confirm",str(npc.dialogue.confirm)%amount,true)
 if int(profile.player.gold)<amount:return owner.window(npc,{},"end",str(npc.dialogue.poor),false)
 var candidate: Dictionary=profile.duplicate(true)
 candidate.player.gold-=amount
 candidate.player.charm=mini(100,int(candidate.player.charm)+5)
 backend.session._profile=candidate
 backend.session._refresh_loyalty()
 if not backend.save():
  backend.session._profile=profile
  return {"ok":false,"reason":"save_failed"}
 backend.publish()
 var kind: String=str(npc.image_types.get(str(profile.character_id),"CHILDBOY"))
 if kind=="CHILDGIRL":kind="CHILDBOY"
 return owner.window(npc,{},"end",str(npc.dialogue.success.get(kind,npc.dialogue.success.CHILDBOY)),false)
