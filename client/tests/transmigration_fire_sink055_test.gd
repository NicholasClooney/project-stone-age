extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 water("sink055")
 print("TRANSMIGRATION_FIRE_SINK055_TEST: %d failures"%failures)
 quit(1 if failures else 0)
