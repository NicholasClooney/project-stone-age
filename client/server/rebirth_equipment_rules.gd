extends RefCounted
## char_item.c:344-354. Raw CHAR_STR/DEX are fixed-point source fields;
## ITEM_NEEDSTR/DEX are compared directly, without division by 100.
## Only level is exempted after rebirth; zero-transmigration defaults persist.
static func requirement_error(level:int,transmigration:int,strength_fixed:int,dexterity_fixed:int,definition:Dictionary)->String:
 if transmigration<=0 and level<int(definition.get("level",0)):return "level"
 if strength_fixed<int(definition.get("need_strength",0)):return "strength"
 if dexterity_fixed<int(definition.get("need_dexterity",0)):return "dexterity"
 if transmigration<int(definition.get("need_transmigration",0)):return "transmigration"
 return ""
