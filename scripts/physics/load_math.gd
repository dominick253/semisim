class_name LoadMath
## Trailer loading and static axle load math (spec section 5.6). Pure math.


static func trailer_mass_loaded(cargo_kg: float) -> float:
	return PHYSICS_CONSTANTS.TRAILER_MASS_EMPTY_KG + cargo_kg


static func combined_mass(cargo_kg: float) -> float:
	return PHYSICS_CONSTANTS.TRACTOR_MASS_KG + trailer_mass_loaded(cargo_kg)


static func trailer_com_loaded(cargo_kg: float) -> Vector3:
	## Mass-weighted CoM of empty trailer plus cargo (trailer-local frame).
	## +z is rearward (toward the bogie); constants carry the corrected signs
	## (see docs/DEVIATIONS.md).
	var m_empty: float = PHYSICS_CONSTANTS.TRAILER_MASS_EMPTY_KG
	var m_total: float = m_empty + cargo_kg
	if m_total <= 0.0:
		return PHYSICS_CONSTANTS.TRAILER_COM_EMPTY
	var e: Vector3 = PHYSICS_CONSTANTS.TRAILER_COM_EMPTY
	var c: Vector3 = PHYSICS_CONSTANTS.CARGO_COM
	return (e * m_empty + c * cargo_kg) / m_total


static func box_inertia(mass_kg: float, extents: Vector3) -> Vector3:
	## Uniform solid box inertia (Ix, Iy, Iz) about its center.
	## extents = full box dimensions (x, y, z): I = m/12 * (sum of the two
	## squared extents perpendicular to the axis).
	return Vector3(
		mass_kg / 12.0 * (extents.y * extents.y + extents.z * extents.z),
		mass_kg / 12.0 * (extents.x * extents.x + extents.z * extents.z),
		mass_kg / 12.0 * (extents.x * extents.x + extents.y * extents.y)
	)


static func trailer_inertia_loaded(cargo_kg: float) -> Vector3:
	## Loaded trailer inertia recomputed as a uniform box of the combined mass.
	return box_inertia(trailer_mass_loaded(cargo_kg), PHYSICS_CONSTANTS.TRAILER_BOX)


static func fifth_wheel_load_kg(cargo_kg: float) -> float:
	## Trailer weight carried by the kingpin, from moments about the trailer
	## bogie axle average. Distances are measured rearward from the kingpin:
	## bogie at +12.20 m, CoM at +6.17..+7.70 m, kingpin at 0.
	var bogie_z: float = (PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_1.z + PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_2.z) * 0.5
	var m_total: float = trailer_mass_loaded(cargo_kg)
	var com: Vector3 = trailer_com_loaded(cargo_kg)
	var lever_com: float = bogie_z - com.z
	var lever_kingpin: float = bogie_z
	return m_total * lever_com / lever_kingpin


static func steer_axle_load_kg(cargo_kg: float) -> float:
	## Static steer (front) axle load in kg, moments about the rear axle.
	## Tractor weight share plus the fifth wheel load acting behind the rear
	## axle at the fifth wheel z offset.
	var m_tractor: float = PHYSICS_CONSTANTS.TRACTOR_MASS_KG
	var rear_z: float = PHYSICS_CONSTANTS.TRACTOR_REAR_AXLE.z
	var front_z: float = PHYSICS_CONSTANTS.TRACTOR_FRONT_AXLE.z
	var wheelbase: float = rear_z - front_z  # 6.50 m
	## Tractor moment about rear axle (CoM ahead of rear axle -> negative z).
	var tractor_moment: float = m_tractor * (rear_z - PHYSICS_CONSTANTS.TRACTOR_COM.z)
	## Fifth wheel load acts at fifth wheel z (behind rear axle -> negative z).
	var fw_kg: float = fifth_wheel_load_kg(cargo_kg)
	var fifth_moment: float = fw_kg * (rear_z - PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER.z)
	return (tractor_moment + fifth_moment) / wheelbase


static func steer_axle_within_cap(load_kg: float) -> bool:
	return load_kg <= PHYSICS_CONSTANTS.STEER_AXLE_LEGAL_CAP_KG
