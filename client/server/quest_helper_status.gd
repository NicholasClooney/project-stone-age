extends RefCounted
## Journal END bits can close one source segment before the helper chain ends.
## Never infer active work from unchecked rows, navigation or optional actions.
const Rules=preload("res://server/original_quests.gd")
static func apply(profile:Dictionary,quest:Dictionary)->void:
 var event:=int(quest.event)
 if event==18:
  # END19 is Hahn's axe; END18 is Barl's axe delivery. The recommendation,
  # permit and outstanding wood continue through the merchant afterwards.
  var items:Array=profile.original_items
  if 2467 in items or 2478 in items or 2468 in items:quest.status="进行中"
 elif event==22:
  # Jan never sets NOW22: accepting Sala's request sets NOW21, and Jan's
  # equipment reward sets END22 before the letter completes END21.
  if not Rules.flag(profile,"ended",22) and Rules.flag(profile,"ended",20) and Rules.flag(profile,"now",21):quest.status="进行中"
