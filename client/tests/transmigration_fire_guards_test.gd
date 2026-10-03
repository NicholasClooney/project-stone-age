extends "res://tests/transmigration_fire_test.gd"
func run()->void:
 guards_and_navigation()
 print("TRANSMIGRATION FIRE GUARDS: %d failures"%failures)
 quit(1 if failures else 0)
