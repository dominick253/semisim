class_name LoadMath
## Trailer loading and static axle load math (spec section 5.6). Pure math.
## Geometry comes from PHYSICS_CONSTANTS (deviations D1..D5 applied).


static func trailer_mass_loaded(cargo_kg: float) -> float:
	return PHYSICS_CONSTANTS.TRAILER_MASS_EMPTY_KG + cargo_kg


static func combined_mass(cargo_kg: float) -> float:
	return PHYSICS_CONSTANTS.TRACTOR_MASS_KG + trailer_mass_loaded(cargo_kg)


static func trailer_com_loaded(cargo_kg: float) -> Vector3:
	## Mass-weighted CoM of empty trailer plus cargo (trailer-local frame,
	## +z rearward from the kingpin).
	var m_empty: float = PHYSICS_CONSTANTS.TRAILER_MASS_EMPTY_KG
	var m_total: float = m_empty + cargo_kg
	if m_total <= 0.0:
		return PHYSICS_CONSTANTS.TRAILER_COM_EMPTY
	var e: Vector3 = PHYSICS_CONSTANTS.TRAILER_COM_EMPTY
	var c: Vector3 = PHYSICS_CONSTANTS.CARGO_COM
	return (e * m_empty + c * cargo_kg) / m_total


static func box_inertia(mass_kg: float, extents: Vector3) -> Vector3:
	## Uniform solid box inertia (Ix, Iy, Iz) about its center.
	## extents = full box dimensions: I = m/12 * (sum of the two squared
	## extents perpendicular to the axis).
	return Vector3(
		mass_kg / 12.0 * (extents.y * extents.y + extents.z * extents.z),
		mass_kg / 12.0 * (extents.x * extents.x + extents.z * extents.z),
		mass_kg / 12.0 * (extents.x * extents.x + extents.y * extents.y)
	)


static func trailer_inertia_loaded(cargo_kg: float) -> Vector3:
	## Loaded trailer inertia recomputed as a uniform box of the combined mass.
	return box_inertia(trailer_mass_loaded(cargo_kg), PHYSICS_CONSTANTS.TRAILER_BOX)


static func bogie_mean_z() -> float:
	return (
		(PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_1.z + PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_2.z) * 0.5
	)


static func fifth_wheel_load_kg(cargo_kg: float) -> float:
	## Trailer weight carried by the kingpin: moments about the bogie axle
	## mean. Kingpin at trailer-local 0, bogie at +10.00, CoM between them.
	var bogie_z: float = bogie_mean_z()
	var m_total: float = trailer_mass_loaded(cargo_kg)
	var com: Vector3 = trailer_com_loaded(cargo_kg)
	var lever_com: float = bogie_z - com.z
	return m_total * lever_com / bogie_z


static func steer_axle_load_kg(cargo_kg: float) -> float:
	## Static steer (front) axle load in kg, moments about the drive axle.
	## Tractor CoM sits ahead of the drive axle (negative z), the fifth wheel
	## load acts at the fifth wheel z (also negative): both load the steer axle.
	var m_tractor: float = PHYSICS_CONSTANTS.TRACTOR_MASS_KG
	var wheelbase: float = (
		PHYSICS_CONSTANTS.TRACTOR_REAR_AXLE.z - PHYSICS_CONSTANTS.TRACTOR_FRONT_AXLE.z
	)
	var tractor_lever: float = -PHYSICS_CONSTANTS.TRACTOR_COM.z
	var fifth_lever: float = -PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER.z
	var fw_kg: float = fifth_wheel_load_kg(cargo_kg)
	return (m_tractor * tractor_lever + fw_kg * fifth_lever) / wheelbase


static func drive_axle_load_kg(cargo_kg: float) -> float:
	return (
		PHYSICS_CONSTANTS.TRACTOR_MASS_KG
		+ fifth_wheel_load_kg(cargo_kg)
		- steer_axle_load_kg(cargo_kg)
	)


static func bogie_axle_load_kg(cargo_kg: float) -> float:
	return trailer_mass_loaded(cargo_kg) - fifth_wheel_load_kg(cargo_kg)


static func steer_axle_within_cap(load_kg: float) -> bool:
	return load_kg <= PHYSICS_CONSTANTS.STEER_AXLE_LEGAL_CAP_KG
