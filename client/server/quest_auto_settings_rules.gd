extends RefCounted
## Shared defaults; movement executors must never accept client speed/cells.
const DEFAULTS={"mode":"A","loot_minutes":30}
const SPEC={"mode":["enum",["A","B","C"]],"loot_minutes":["int",1,180]}
const C_MAX_CELLS:=3
const C_SPEED_MULTIPLIER:=2.0
static func effective(overrides:Dictionary)->Dictionary:
 var result:Dictionary=DEFAULTS.duplicate()
 var quest=overrides.get("quest",{})
 if quest is Dictionary:
  if quest.get("mode") in ["A","B","C"]:result.mode=quest.mode
  var minutes=quest.get("loot_minutes",30)
  if (minutes is int or minutes is float) and is_finite(float(minutes)) and float(minutes)==floor(float(minutes)) and minutes>=1 and minutes<=180:result.loot_minutes=int(minutes)
 return result
