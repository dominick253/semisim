# CITYHAUL Physics Spec

Authoritative prose version of the Phase 1 physics model. The single source of
truth for code constants is `scripts/physics/PHYSICS_CONSTANTS.gd`. A constant
change must update both files in the same commit.

## 0. Coordinate convention

-Z is forward (Godot convention, vehicles face -Z), +Y up, +X left. Tractor
origin: rear (drive) axle contact patch. Trailer origin: kingpin, trailer body
extending toward +Z (rearward). Deviations D1, D4 and D5 in
`docs/DEVIATIONS.md` correct spec values that violated this convention.

## 1. Architecture

Hybrid model. Two `RigidBody3D` bodies (tractor, trailer) joined by one
`Generic6DOFSpringConstraint3D` that locks 5 degrees of freedom and frees only
yaw about the kingpin axis. Articulation spring, damping and friction torques
are applied by code every physics tick (full control; Jolt enforces the hard
limits). Wheels are custom raycast suspension and tire force nodes, not
`VehicleBody3D`. Physics engine: Jolt. Physics ticks: 120/s. Max physics steps
per frame: 16.

## 2. Rigid bodies

Tractor:
- Mass: 8400 kg.
- Origin: rear (drive) axle contact patch.
- Rear axle center: (0, 0.563, 0.00). Front axle center: (0, 0.554, -6.50).
- CoM: (0, 1.30, -0.75). Fifth wheel center: (0, 1.30, -4.55) (D1: spec value
  -7.45 is ahead of the steer axle and physically impossible; -4.55 is the
  real tandem position between the axles).
- Box: 2.50 x 3.30 x 10.50 m. Inertia as a uniform box: Ix 84,798,
  Iy 81,550, Iz 11,998 kg m^2 (D8: recomputed from the spec's own method).

Trailer:
- Mass empty: 7000 kg.
- Origin: the kingpin.
- Bogie axle centers: (0, 0.563, 11.80) and (0, 0.563, 12.60).
- CoM empty: (0, 1.55, +7.70) (D4: sign corrected to the bogie side).
- Box: 2.59 x 4.07 x 16.15 m.
- Inertia empty (uniform box): Ix 161,809, Iy 156,060, Iz 13,576 kg m^2
  (D9: recomputed from the spec's own method).

## 3. Tire model (Pacejka magic formula, per wheel)

- Lateral: `Fy = D * sin(C * atan(B * alpha))`, B = 10.0, C = 1.60,
  `D = mu * Fz`. alpha clamped to +/- 1.4 rad.
- Longitudinal driving: `Fx = Dx * sin(Cx * atan(Bx * kappa))`, Bx = 12.0,
  Cx = 1.40, `Dx = mu * Fz`.
- Longitudinal braking: same curve with `Bx_brake = 14.0`.
- Combined slip: friction ellipse. `u_long = |Fx| / (mu*Fz)` clamped to 1.0,
  `Fy_avail = mu*Fz*sqrt(max(0, 1 - u_long^2))`.
- ABS: engages at slip ratio > 0.15, releases at slip < 0.08.

Per-tire table:

| Position | Size | Width | Rolling radius | mu dry | mu wet | mu ice |
|---|---|---|---|---|---|---|
| Steer (2) | 295/75R22.5 | 0.295 m | 0.554 m | 1.10 | 0.70 | 0.25 |
| Drive (2) | 11R22.5 | 0.285 m | 0.563 m | 1.15 | 0.72 | 0.25 |
| Trailer (4) | 11R22.5 | 0.285 m | 0.563 m | 1.10 | 0.70 | 0.25 |

Load transfer: quasi-static per axle pair from longitudinal and lateral
acceleration, capped at 18 percent transfer per pair. If any wheel normal load
drops below 5 percent of static, trigger the rollover check; combination
rollover threshold lateral acceleration 0.45 g.

## 4. Engine, transmission, retarder

Engine torque curve (rpm -> Nm): 0->0, 700->1200, 1000->2100, 1400->2230,
1600->2100, 1800->1600. Idle 700 rpm, redline 1800 rpm, shutdown 1900 rpm.
Engine braking (throttle closed): 1800 rpm -> 400 Nm, linear to 700 rpm ->
120 Nm. Flywheel inertia 1.2 kg m^2.

Clutch: capacity 3500 Nm; torque = pedal_engagement x capacity; engagement is
smoothstep over pedal travel 0.20 to 0.80.

10-speed transmission (5 low range, 5 high range). Ratios: high 1 to 5 =
4.834, 2.857, 1.840, 1.290, 1.000. Low 6 to 10 = 9.015, 5.324, 3.427, 2.403,
1.864. Reverse R = 8.315. Automatic mode (toggle V) upshifts at 1550 rpm,
downshifts at 1150 rpm.

Final drive 3.70, open differential, driveline efficiency 0.94, driveline
inertia 0.5 kg m^2. Speed at 1800 rpm in direct drive with 0.563 m rolling
radius is about 107 km/h. Top speed governor: fuel cut above 120 km/h with HUD
flash.

Gear rules: R selectable only below 0.5 m/s. Any gear change requires clutch
depressed or automatic mode; otherwise the shift is a no-op with a grind sound
and a HUD flash.

Retarder: 5 stages, driveshaft retarding force 50, 100, 150, 200, 250 kN.
Active only in high range, gears 1 to 4, speed above 15 km/h.

## 5. Brakes and the air brake system

Service brake torques: front axle 9,000 Nm/axle, trailer 10,000 Nm/axle, drive
12,000 Nm/axle. Parking brake: drive axle only, 12,000 Nm. Trailer brake is
integrated with the service brake in Phase 1 (separate trailer valve is
Phase 3).

Air system: nominal 100 psi. Compressor fill rate `2.22 * (rpm / 700)` psi/s.
Warning below 60 psi (HUD + audible low-air buzzer). Spring brake applies
automatically below 40 psi: drive and trailer axles lock until pressure
recovers above 60 psi or the engine is restarted.

Target behavior (unit-tested): full service brake plus retarder from 80 km/h
on dry stops in 24 to 34 m.

## 6. Kingpin and articulation

- Hard limits +/- 75 deg. Jackknife warning at +/- 60 deg.
- Self-centering spring: `T = -8000 * theta` Nm.
- Damping: `T = -12000 * theta_rate` Nm.
- Kingpin friction (Stribeck): 15,000 Nm static, 10,000 Nm kinetic, transition
  at |theta_rate| = 0.05 rad/s.
- Jackknife event: |theta| > 70 deg, or |theta| > 55 deg with |theta_rate| >
  25 deg/s. Effect: state JACKKNIFE, throttle input ignored, camera shake
  0.3 s, challenge fail. Recovery only via restart.
- Trailer pushover is not a special case; it must emerge from the hinge plus
  brake torques.

## 7. Loading (loaded vs unloaded)

Cargo mass slider 0 to 29,000 kg, default 20,000 kg. Cargo CoM (trailer-local)
(0, 1.70, +9.41) (D5: sign corrected, magnitude set so the full 29,000 kg load
reproduces the spec's own 7,417 kg steer axle target instead of overloading the
combination 2x). Combined trailer CoM recomputed by mass weighting: empty
(0, 1.55, +7.70), full 29,000 kg -> (0, 1.671, +9.078) (D6). Trailer inertia
recomputed as a uniform box of the combined mass (full: Iy 802,592 kg m^2, D7).
Combined combination mass 44,400 kg. Static steer axle load: 2,777 kg empty,
7,419 kg full (D10), both at or under the pinned 7,711 kg cap in tests.

## 8. Suspension and steering

Raycast suspension per wheel: spring 55,000 N/m (steer), 65,000 N/m (drive and
trailer), damper 3,500 N s/m, travel +/- 0.12 m. Anti-roll bars: tractor front
30,000 N/m, tractor rear 45,000 N/m, trailer bogie 35,000 N/m.

Steering: max steer angle `35 deg * max(0.35, 1 - v / 55)` (v in m/s).
Keyboard steer rate 120 deg/s, gamepad 90 deg/s with auto-centering. Kingpin
inclination 7.7 deg, scrub radius 0.025 m. Full lock = 2.5 visual steering
wheel turns from center. Targets: tractor alone curb-to-curb turning radius
7.6 m; loaded combination off-tracking under 1.2 m on a 15 m radius circle at
12 km/h.

## 9. Collision and damage

Convex decomposition collision from the GLB (`scene_import` option, max 16
convex pieces per body), `contact_monitor = true`, `max_contacts_reported = 8`.
Wall or building contacts above 15 kN count as a strike; 3 strikes fail the
challenge. Cone contacts are never strikes but count in scoring. Damage is a
counter plus HUD state in Phase 1; component damage is Phase 2.
