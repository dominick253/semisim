extends Node3D
## What sustained yaw torque actually articulates the combination? Reports the
## articulation angle reached at the end of the push so the integration test can
## pick a magnitude with real headroom over the bogie tires' yaw resistance.


func _ready() -> void:
	var torques: Array = [5.0e5, 2.0e6, 5.0e6, 2.0e7, 5.0e7]
	for tq in torques:
		var harness: Node = load("res://tests/sim/combination_rest_harness.tscn").instantiate()
		add_child(harness)
		await harness.settle(120)
		var before: float = harness.controller.articulation_rad()
		harness.push_yaw(tq, 60)
		await harness.settle(60)
		var during: float = harness.controller.articulation_rad()
		print(
			"torque=",
			tq,
			" before=",
			snappedf(before, 0.0001),
			" during=",
			snappedf(during, 0.0001),
			" delta_deg=",
			snappedf(rad_to_deg(during - before), 0.01),
			" kp_gap=",
			snappedf(harness.kingpin_gap_m(), 0.001)
		)
		await harness.settle(120)
		print(
			"   after release: artic_deg=",
			snappedf(rad_to_deg(harness.controller.articulation_rad()), 0.01),
			" kp_gap=",
			snappedf(harness.kingpin_gap_m(), 0.001)
		)
		harness.free()
	get_tree().quit()
