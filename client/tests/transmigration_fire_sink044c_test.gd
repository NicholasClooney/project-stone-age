extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 water("sink044c")
 print("TRANSMIGRATION_FIRE_SINK044C_TEST: %d failures"%failures)
 quit(1 if failures else 0)
