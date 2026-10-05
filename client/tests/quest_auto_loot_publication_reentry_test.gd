extends "res://tests/quest_auto_loot_publication_test.gd"
## Same production queue; no derived publish observer substitute.
func run()->void:
 await publication_modes(["success_save","success_stop","success_identity","failure_stop","failure_identity"],"QUEST AUTO LOOT PUBLICATION REENTRY")
