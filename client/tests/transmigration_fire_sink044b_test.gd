extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 water("sink044b")
 print("TRANSMIGRATION_FIRE_SINK044B_TEST: %d failures"%failures)
 quit(1 if failures else 0)
