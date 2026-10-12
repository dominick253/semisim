class_name TrailerPath
## Trailer path prediction for the G overlay (section 11): 30 m of predicted
## path from the current articulation and steer angle, recomputed every 0.25 s.
##
## Pure geometry in the XZ plane, sampled by arc length along the kingpin path
## so the prediction does not depend on the physics tick. Angles are radians; a
## Vector2 is (x, z) and heading 0 points along +X, increasing toward +Z.
##
## Kinematics: the kingpin tracks the tractor heading, and the bogie trails it
## by the pinned kingpin-to-bogie distance along the trailer heading. Holding
## the current steer and articulation over the lookahead is what makes the
## overlay show the trailer cutting the corner.

const SAMPLE_STEP_M: float = (
	PHYSICS_CONSTANTS.TRAILER_PATH_LENGTH_M / float(PHYSICS_CONSTANTS.TRAILER_PATH_SAMPLES)
)


static func path_points(
	kingpin: Vector2, heading_rad: float, articulation_rad: float, steer_rad: float
) -> PackedVector2Array:
	## Predicted bogie positions, TRAILER_PATH_SAMPLES + 1 points.
	return _arc(kingpin, heading_rad, articulation_rad, steer_rad, true)


static func tractor_path_points(
	kingpin: Vector2, heading_rad: float, steer_rad: float
) -> PackedVector2Array:
	## The kingpin's own predicted path, for the overlay comparison.
	return _arc(kingpin, heading_rad, 0.0, steer_rad, false)


static func curvature(steer_rad: float) -> float:
	## 1 / radius of the kingpin path. Bicycle model: the kingpin tracks the
	## tractor heading, so its curvature is the yaw rate divided by speed.
	if absf(steer_rad) < 1e-6:
		return 0.0
	return tan(steer_rad) / PHYSICS_CONSTANTS.WHEELBASE_TRACTOR_M


static func bogie_radius_m(steer_rad: float, articulation_rad: float) -> float:
	## Radius of the circle the bogie follows at a held steer and articulation,
	## measured from the turn center. INF when running straight.
	##
	## Derivation: with signed turn radius R = 1 / k the center sits at
	## kingpin + R * dir(heading + 90 deg). Bogie = kingpin - L * dir(heading +
	## articulation), and both rotate about the center at the same rate, so the
	## bogie radius is constant at sqrt(R^2 + L^2 + 2 R L sin(articulation)).
	var k: float = curvature(steer_rad)
	if absf(k) < 1e-9:
		return INF
	var radius: float = 1.0 / k
	var length: float = PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M
	return sqrt(radius * radius + length * length + 2.0 * radius * length * sin(articulation_rad))


static func steady_state_articulation_rad(steer_rad: float) -> float:
	## The articulation a trailer settles at for a held steer. Requiring the
	## bogie velocity to lie along the trailer axis (no lateral scrub) resolves
	## the bogie velocity to v cos(a) along the axis and v (sin(a) + L / R)
	## across it, so sin(articulation) = -L / R and the bogie radius collapses
	## to sqrt(R^2 - L^2), inside the tractor path. Returns 0 when the turn
	## radius is tighter than the kingpin-to-bogie distance, where the trailer
	## would be dragged sideways instead of following.
	var k: float = curvature(steer_rad)
	if absf(k) < 1e-9:
		return 0.0
	var radius: float = 1.0 / k
	var length: float = PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M
	if absf(radius) <= length:
		return 0.0
	var magnitude: float = asin(clampf(length / radius, -1.0, 1.0))
	return -magnitude if k > 0.0 else magnitude


static func _arc(
	kingpin: Vector2, heading_rad: float, articulation_rad: float, steer_rad: float, trailer: bool
) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var k: float = curvature(steer_rad)
	var length: float = PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M
	for i in PHYSICS_CONSTANTS.TRAILER_PATH_SAMPLES + 1:
		var s: float = float(i) * SAMPLE_STEP_M
		var point: Vector2 = _kingpin_at(kingpin, heading_rad, k, s)
		if trailer:
			# Bogie = kingpin - L along the trailer heading, which is the
			# tractor heading rotated by the articulation.
			point -= length * _dir(heading_rad + k * s + articulation_rad)
		out.append(point)
	return out


static func _kingpin_at(origin: Vector2, heading_rad: float, k: float, s: float) -> Vector2:
	## Closed form of the arc integral, exact for constant curvature:
	## integral of dir(heading_rad + k*u) du from 0 to s = (perp(h+ks) - perp(h)) / k.
	if absf(k) < 1e-9:
		return origin + s * _dir(heading_rad)
	var delta: Vector2 = _perp(heading_rad + k * s) - _perp(heading_rad)
	return origin + delta / k


static func _dir(angle_rad: float) -> Vector2:
	return Vector2(cos(angle_rad), sin(angle_rad))


static func _perp(angle_rad: float) -> Vector2:
	## The heading direction rotated -90 deg, whose derivative is the heading.
	return Vector2(sin(angle_rad), -cos(angle_rad))
