extends GutTest
## T6..T14: loading, inertia, kingpin friction, air system, coupling,
## jackknife, reverse lock and steer axle limit (spec section 15).
## Where the spec's stated numbers do not follow from the spec's own
## formulas, the formula output is asserted and the divergence is logged in
## docs/DEVIATIONS.md. Scripts register global class names, so no preloads.


func test_t6_load_shift() -> void:
	# 29,000 kg cargo -> trailer mass 36,000 kg and mass-weighted CoM.
	# Corrected geometry (docs/DEVIATIONS.md D4/D5): empty (0,1.55,+6.00),
	# cargo (0,1.70,+6.51), +z rearward from the kingpin. Spec target
	# (0,1.794,-6.58) is not the mass weighting of the spec's own values (D10).
	assert_eq(LoadMath.trailer_mass_loaded(29000.0), 36000.0, "T6 loaded trailer mass")
	var com: Vector3 = LoadMath.trailer_com_loaded(29000.0)
	assert_almost_eq(com.y, 1.671, 0.05, "T6 CoM y")
	assert_almost_eq(com.z, 6.411, 0.05, "T6 CoM z")
	assert_almost_eq(com.x, 0.0, 0.05, "T6 CoM x")


func test_t7_inertia_growth() -> void:
	# Loaded trailer inertia as a uniform box of the combined mass.
	# Spec claims Iy 486,000; uniform box of 36,000 kg over 2.59 x 4.07 x
	# 16.15 m gives Iy 802,592. See docs/DEVIATIONS.md.
	var inertia: Vector3 = LoadMath.trailer_inertia_loaded(29000.0)
	assert_between(inertia.y, 802592.0 * 0.9, 802592.0 * 1.1, "T7 loaded Iy (uniform box)")
	assert_gt(inertia.y, PHYSICS_CONSTANTS.TRAILER_IY_EMPTY_KG_M2, "T7 inertia grows with load")


func test_t8_kingpin_friction() -> void:
	# Stribeck: 15,000 Nm static, 10,000 Nm kinetic at rate 0.2 rad/s.
	assert_eq(KingpinModel.static_friction_max_nm(), 15000.0, "T8 static friction")
	var kinetic: float = absf(KingpinModel.friction_torque_nm(0.2))
	assert_between(kinetic, 10000.0 * 0.9, 10000.0 * 1.1, "T8 kinetic at 0.2 rad/s")
	var boundary: float = absf(KingpinModel.friction_torque_nm(0.05))
	assert_between(boundary, 10000.0 * 0.9, 10000.0 * 1.1, "T8 kinetic at transition rate")


func test_t9_air_fill() -> void:
	# 700 rpm from 0 psi reaches 100 psi in 45 s +/- 5 s.
	var air: AirSystem = AirSystem.new()
	air.reset(0.0, true)
	var t: float = 0.0
	var reached_s: float = -1.0
	while t < 60.0:
		air.step(0.5, 700.0)
		t += 0.5
		if air.pressure_psi >= 100.0:
			reached_s = t
			break
	assert_gt(reached_s, 0.0, "T9 pressure reaches 100 psi")
	assert_between(reached_s, 40.0, 50.0, "T9 fill time 45 s +/- 5 s")


func test_t10_air_alarm_and_spring_brake() -> void:
	# Alarm at 59 psi, spring brake engaged at 39 psi.
	var air: AirSystem = AirSystem.new()
	air.reset(60.0, false)
	air.consume_psi(1.0)  # 59 psi
	assert_true(air.warning_active(), "T10 alarm at 59 psi")
	assert_eq(air.state, AirSystem.AirState.WARNING, "T10 warning state at 59 psi")
	air.consume_psi(20.0)  # 39 psi
	assert_true(air.spring_brake_engaged, "T10 spring brake engaged at 39 psi")
	assert_eq(air.state, AirSystem.AirState.SPRING_BRAKE, "T10 spring brake state")


func test_t11_coupling() -> void:
	# 0.2 m off, 5 deg articulation, 0.3 m/s -> locks. 15 deg -> no lock.
	var c: CouplingController = CouplingController.new()
	assert_true(c.can_auto_lock(0.2, 5.0, 0.3), "T11 lock at 0.2 m, 5 deg, 0.3 m/s")
	assert_false(c.can_auto_lock(0.2, 15.0, 0.3), "T11 reject at 15 deg")
	assert_false(c.can_auto_lock(0.4, 5.0, 0.3), "T11 reject at 0.4 m")
	assert_false(c.can_auto_lock(0.2, 5.0, 0.6), "T11 reject at 0.6 m/s")


func test_t12_jackknife() -> void:
	# 71 deg -> jackknife condition (state machine locks throttle in the
	# vehicle controller; the rule itself is tested here).
	assert_true(KingpinModel.is_jackknife(71.0, 0.0), "T12 angle rule 71 deg")
	assert_true(KingpinModel.is_jackknife(-71.0, 0.0), "T12 negative angle rule")
	assert_true(KingpinModel.is_jackknife(60.0, 30.0), "T12 rate rule 55 deg + 25 deg/s")
	assert_false(KingpinModel.is_jackknife(60.0, 10.0), "T12 no jackknife at 60 deg slow")
	assert_false(KingpinModel.is_jackknife(50.0, 30.0), "T12 no jackknife below 55 deg")


func test_t13_reverse_lock() -> void:
	# R pressed at 1.0 m/s -> no gear change, warning emitted.
	var t: Transmission = Transmission.new()
	t.reset()
	t.gear = 3
	var accepted: bool = t.select_gear(-1, 1.0, true)
	assert_false(accepted, "T13 reverse rejected at 1.0 m/s")
	assert_eq(t.gear, 3, "T13 gear unchanged")
	assert_gt(t.last_reject_reason.length(), 0, "T13 warning reason emitted")


func test_t14_steer_axle_limit() -> void:
	# Static steer axle load with the corrected geometry (D1..D5):
	# 5,859 kg empty (spec 5,886) and 7,416 kg full (spec 7,417). Both under the
	# pinned 7,711 kg cap. The spec's original geometry cannot produce these
	# numbers; the corrected geometry reproduces the spec's own targets.
	var empty_load: float = LoadMath.steer_axle_load_kg(0.0)
	var full_load: float = LoadMath.steer_axle_load_kg(29000.0)
	assert_between(
		empty_load, 5886.0 * 0.98, 5886.0 * 1.02, "T14 empty steer load matches spec target"
	)
	assert_between(
		full_load, 7417.0 * 0.98, 7417.0 * 1.02, "T14 full steer load matches spec target"
	)
	assert_gt(full_load, empty_load, "T14 load grows with cargo")
	assert_true(LoadMath.steer_axle_within_cap(empty_load), "T14 empty load under cap")
	assert_true(LoadMath.steer_axle_within_cap(full_load), "T14 full load under cap")
	assert_false(LoadMath.steer_axle_within_cap(7712.0), "T14 cap check rejects over-cap load")
