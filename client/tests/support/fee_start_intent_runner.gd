extends "res://server/quest_auto.gd"
var mode := ""
var attempted := false
func install_fee_start(b,prepared:Dictionary,staged:RefCounted)->void:
 attempted=true
 if mode=="no_install":return
 if mode=="copied_prepared":super.install_fee_start(b,prepared.duplicate(true),staged);return
 if mode=="wrong_identity":super.install_fee_start(b,prepared,preload("res://server/quest_auto_state.gd").new());return
 super.install_fee_start(b,prepared,staged)
 if mode=="post_install_binding":b.fee_attach(71)
