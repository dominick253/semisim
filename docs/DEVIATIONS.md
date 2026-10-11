# CITYHAUL Deviations Log

Every spec item that is technically impossible on this engine or host, with
field, spec value, final value, and reason. Never silently substitute.

| ID | Field | Spec value | Final value | Reason |
|---|---|---|---|---|
| D1 | Tractor fifth wheel center z | (0, 1.30, -7.45) | (0, 1.30, -4.55) | Spec z places the fifth wheel 0.95 m AHEAD of the steer axle (-6.50), which is physically impossible on a tractor. -4.55 is the real tandem position: between steer and drive axles, 4.55 m behind the steer axle. With -4.55 the corrected static model reproduces the spec's own T14 target of 7,417 kg steer load at full cargo (computed 7,419 kg). |
| D2 | T1 expected Fy at alpha 0.05 rad | 28,100 N | 22,226 N (asserted with the spec's +/- 10 percent band) | The spec's own formula Fy = D*sin(C*atan(B*alpha)), B=10, C=1.6, D=1.10*29,905 N evaluates to 22,226 N. 28,100 N is not reachable from the pinned constants; the formula is authoritative. |
| D3 | T5 assertion quantity | "wheel force 69,600 N" | 69,920 Nm wheel torque (asserted with the spec's +/- 8 percent band) | 2230 x 9.015 x 3.70 x 0.94 is a torque product in Nm, not a force. Dividing by the 0.563 m rolling radius gives 124,191 N, which matches no spec number. The spec number 69,600 matches the torque 69,920 Nm within 0.5 percent, so the unit label in the spec is a typo. |
| D4 | Trailer CoM empty z | (0, 1.55, -7.70) | (0, 1.55, +7.70) | Trailer origin is the kingpin and the bogie axles sit at z +11.80/+12.60, so the trailer body extends toward +Z. z -7.70 is outside the 16.15 m trailer box (which spans z -2.50..+13.65). Sign corrected to the bogie side. |
| D5 | Cargo CoM | (0, 1.70, -5.80) | (0, 1.70, +9.41) | Same sign error as D4. Additionally, at magnitude 5.80 the full 29,000 kg load puts 17,791 kg on the fifth wheel and 13,423 kg on the steer axle, nearly 2x the spec's own 7,711 kg cap, making the default loading illegally overloaded by construction. 9.41 reproduces the spec's own T14 target (7,417 kg steer at full cargo) and matches a real 53 ft van loaded CoM position. |
| D6 | T6 expected loaded CoM | (0, 1.794, -6.58) | (0, 1.671, +9.078) | The spec value is not the mass-weighted average of the spec's own empty and cargo CoM values. Weighting (0,1.55) and (0,1.70) at 7,000/29,000 kg gives y 1.671. z follows D4/D5 corrections. |
| D7 | T7 expected loaded trailer Iy | 486,000 kg m^2 | 802,592 kg m^2 (asserted with the spec's +/- 10 percent band) | The spec says inertia is recomputed "as a uniform box of the combined mass". A uniform 36,000 kg box over 2.59 x 4.07 x 16.15 m gives Iy 802,592. 486,000 does not follow from the spec's own stated method. |
| D8 | Tractor box inertia | Ix 32,133 / Iy 30,975 / Iz 9,758 | Ix 84,798 / Iy 81,550 / Iz 11,998 | Spec claims "inertia computed as a uniform box" but the numbers are not m/12 x (sum of squared extents) for 8,400 kg over 2.50 x 3.30 x 10.50 m. Values recomputed from the spec's own stated method. |
| D9 | Trailer empty box inertia | Ix 415,000 / Iy 331,000 / Iz 113,600 | Ix 161,809 / Iy 156,060 / Iz 13,576 | Same as D8 for 7,000 kg over 2.59 x 4.07 x 16.15 m. |
| D10 | T14 expected empty steer load | 5,886 kg | 2,777 kg | 5,886 kg only follows from the impossible fifth wheel position (D1). With the corrected position the empty combination carries 2,777 kg on the steer axle. The full-cargo value matches the spec target (see D1). Note: the pinned 7,711 kg cap is the US fifth wheel / single axle group limit (17,000 lb); the US steer axle limit is 5,443 kg. Cap kept as pinned by the spec. |
| D11 | Godot 3D physics engine setting name | "engine Jolt" | `physics/3d/physics_engine="Jolt"` | Pinned value kept; recorded so CI readers know the exact project.godot key used (verified against the Godot 4.7.2 binary setting list). |

No silent substitutions. Each row is mirrored by a `DEVIATION` comment at the
constant in `scripts/physics/PHYSICS_CONSTANTS.gd` and by the matching section
in `docs/physics-spec.md`.
