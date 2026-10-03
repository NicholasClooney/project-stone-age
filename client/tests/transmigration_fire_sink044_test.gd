extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 water("sink044")
 print("TRANSMIGRATION_FIRE_SINK044_TEST: %d failures"%failures)
 quit(1 if failures else 0)
