extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 water("sink044a")
 print("TRANSMIGRATION_FIRE_SINK044A_TEST: %d failures"%failures)
 quit(1 if failures else 0)
