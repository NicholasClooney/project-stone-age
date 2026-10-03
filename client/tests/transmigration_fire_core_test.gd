extends "res://tests/transmigration_fire_test.gd"
## Core route/savefail isolated from the long sixty-conversion matrix.
func run()->void:
 core()
 print("TRANSMIGRATION FIRE CORE: %d failures"%failures)
 quit(1 if failures else 0)
