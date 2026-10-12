class_name TurnEnvelope
## The 90 degree turn envelope from docs/world-spec.md section 2.
##
## A loaded combination turning a corner sweeps two radii: the kingpin follows
## the outer path and the bogie cuts the inner path, with
## bogie radius = sqrt(kingpin radius squared minus lever squared), where the
## lever is the pinned kingpin to bogie distance. The model is validated by the
## Phase 1 measurement in D27: predicted bogie radius 11.18 m on a 15 m circle
## against 11.18 m measured.
##
## A turn is possible when a kingpin path exists that stays inside the outer
## boundary (inner fillet plus street width, minus clearance) while the bogie
## stays outside the inner boundary (inner fillet plus clearance).

# Half trailer box width 1.295 plus the accepted kingpin plate error 0.50 (D36)
# plus the handling margin in WorldConstants. Asserted against PHYSICS_CONSTANTS
# in tests/unit/test_turn_envelope.gd rather than trusted.
const CLEARANCE_M: float = 2.295

# A turn below this angle is a straight run and needs no envelope allowance.
const STRAIGHT_ANGLE_DEG: float = 20.0


static func lever_m() -> float:
	return PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M


static func bogie_radius_m(kingpin_radius_m: float) -> float:
	var inner: float = kingpin_radius_m * kingpin_radius_m - lever_m() * lever_m()
	if inner < 0.0:
		return -1.0
	return sqrt(inner)


static func required_outer_radius_m(fillet_m: float) -> float:
	return (
		CLEARANCE_M
		+ sqrt((fillet_m + CLEARANCE_M) * (fillet_m + CLEARANCE_M) + lever_m() * lever_m())
	)


static func min_street_width_m(fillet_m: float) -> float:
	return required_outer_radius_m(fillet_m) - fillet_m


static func turn_fits(street_width_m: float, fillet_m: float) -> bool:
	return street_width_m >= min_street_width_m(fillet_m) - 0.001


static func street_width_m(kind: String) -> float:
	if WorldConstants.STREET_WIDTH_M.has(kind):
		return WorldConstants.STREET_WIDTH_M[kind]
	return WorldConstants.STREET_WIDTH_M["tight"]


static func corner_fillet_m(kind: String) -> float:
	if WorldConstants.CORNER_FILLET_M.has(kind):
		return WorldConstants.CORNER_FILLET_M[kind]
	return WorldConstants.CORNER_FILLET_M["tight"]


static func turn_angle_deg(from_pos: Vector3, through_pos: Vector3, to_pos: Vector3) -> float:
	var inbound: Vector3 = through_pos - from_pos
	var outbound: Vector3 = to_pos - through_pos
	inbound.y = 0.0
	outbound.y = 0.0
	if inbound.length() < 0.01 or outbound.length() < 0.01:
		return 0.0
	var angle: float = rad_to_deg(inbound.angle_to(outbound))
	if angle > 90.0:
		angle = 180.0 - angle
	return angle


static func junction_fits(
	from_kind: String, from_width_m: float, to_kind: String, to_width_m: float
) -> bool:
	# The usable corner at a junction is the wider of the two fillets: a truck
	# turns an alley into an arterial by swinging around the arterial corner.
	var width: float = max(from_width_m, to_width_m)
	var fillet: float = max(corner_fillet_m(from_kind), corner_fillet_m(to_kind))
	return turn_fits(width, fillet)
