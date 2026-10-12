extends GutTest
## T1..T5: tire model and gear torque unit tests (spec section 15).
## Pure-math checks against scripts/physics/tire_model.gd.

const TireModel := preload("res://scripts/physics/tire_model.gd")


func test_t1_tire_lateral() -> void:
	# Spec T1 states 28,100 N, but the spec formula B=10, C=1.6, D=mu*Fz
	# evaluates to 22,226 N at alpha 0.05. See docs/DEVIATIONS.md. Assert the
	# formula output with the spec's +/- 10 percent band.
	var mu: float = 1.10
	var fz: float = 29905.0
	var fy: float = TireModel.lateral_force(0.05, fz, mu)
	assert_between(absf(fy), 22226.0 * 0.9, 22226.0 * 1.1, "T1 lateral force")


func test_t2_tire_peak() -> void:
	# alpha 0.20 rad same load -> Fy 32,700 N +/- 10 percent, at least 95
	# percent of peak D
	var mu: float = 1.10
	var fz: float = 29905.0
	var fy: float = TireModel.lateral_force(0.20, fz, mu)
	assert_between(absf(fy), 32700.0 * 0.9, 32700.0 * 1.1, "T2 force at alpha 0.20")
	var peak: float = TireModel.lateral_peak(fz, mu)
	assert_gt(absf(fy) / peak, 0.95, "T2 at least 95 percent of peak")


func test_t3_load_linearity() -> void:
	# doubling Fz doubles peak D within 15 percent
	var mu: float = 1.10
	var fz: float = 29905.0
	var peak_single: float = TireModel.lateral_peak(fz, mu)
	var peak_double: float = TireModel.lateral_peak(fz * 2.0, mu)
	assert_between(peak_double / peak_single, 2.0 * 0.85, 2.0 * 1.15, "T3 load linearity")


func test_t4_wheel_torque_peak() -> void:
	# peak Fy x 0.554 m = 18,200 Nm +/- 10 percent
	var mu: float = 1.10
	var fz: float = 29905.0
	var peak_fy: float = TireModel.lateral_peak(fz, mu)
	var torque: float = peak_fy * 0.554
	assert_between(torque, 18200.0 * 0.9, 18200.0 * 1.1, "T4 peak wheel torque")


func test_t5_gear_torque() -> void:
	# 2230 Nm x 9.015 x 3.70 x 0.94 = 69,920 Nm wheel torque. The spec labels
	# this "wheel force 69,600 N"; the quantity is a torque in Nm (see
	# docs/DEVIATIONS.md). Assert the torque with the spec's +/- 8 percent band.
	var engine_nm: float = 2230.0
	var gear_ratio: float = 9.015
	var wheel_torque_nm: float = TireModel.wheel_traction_torque(
		engine_nm,
		gear_ratio,
		PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO,
		PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	assert_between(wheel_torque_nm, 69600.0 * 0.92, 69600.0 * 1.08, "T5 wheel torque")
