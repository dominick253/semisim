# CITYHAUL World Spec (Phase 2, M1)

Every number here is derived from a pinned constant or a Phase 1 measurement.
Nothing here is set from taste. Pending measurements are marked as pending, not
guessed.

## 1. Inputs this spec is allowed to use

| Input | Value | Source |
|---|---|---|
| Kingpin to bogie distance L | 10.00 m | `PHYSICS_CONSTANTS` (D3) |
| Trailer body width | 2.60 m | `PHYSICS_CONSTANTS` trailer box |
| Measured bogie path radius on a 15 m circle | 11.18 m | D27, steer path 16.32 m minus 5.14 m measured off-tracking |
| Geometric bogie path radius on a 15 m circle | 11.18 m | sqrt(15.00^2 - 10.00^2), matches the measurement exactly |
| Measured kingpin plate drift | 0.44 m | D36 |
| Phase 1 alley inner width | 8.00 m | `ALLEY_INNER_X_WEST` -40.0, `ALLEY_INNER_X_EAST` -32.0 |
| Phase 1 alley length | 60.0 m | `ALLEY_MIN_Z` -15.0 to `ALLEY_MAX_Z` 45.0 |
| Yard draw-call budget | 80 | Phase 1 build spec section 7 |
| Yard FPS | mean 198.00, p50 210.00, p05 160.00 | gate G3, `docs/evidence/phase1/fps_yard.txt`, 60.0 s drive, 11894 frames, llvmpipe 1280x720, 120.13 physics Hz |

The geometric model and the live physics agree on the bogie radius (11.18 m
against 11.18 m measured). The disagreement in D27 is about the reference path
(kingpin 15.00 m versus steer axle 16.32 m), not about the trailer. That is why
this spec can size streets from the geometric model.

## 2. The 90 degree turn envelope rule

A loaded combination turning 90 degrees at an intersection sweeps two different
radii: the kingpin follows the outer path, the bogie cuts the inner path.

```
R_bogie = sqrt(R_kingpin^2 - L^2),  L = 10.00 m
```

Let `Ri` be the inner curb fillet radius, `W` the curb-to-curb street width, so
the outer boundary sits at `Ri + W`. Clearance `c` is the room the body needs on
each side of its path:

```
c = half body width + kingpin plate error + handling margin
  = 1.30 + 0.44 + 0.50 = 2.24 m
```

The turn is possible when a kingpin path exists that stays inside the outer
boundary while the bogie stays outside the inner boundary:

```
Ri + W - c  >=  sqrt((Ri + c)^2 + L^2) + c
W_min(Ri)   =  c + sqrt((Ri + c)^2 + 100.0) - Ri
```

`TurnEnvelope` in `scripts/world/turn_envelope.gd` implements this and the graph
validator asserts it for every turn in every delivery route.

### Required width per inner fillet radius

| Inner fillet Ri (m) | Minimum width W_min (m) |
|---|---|
| 0 | 12.49 |
| 2 | 11.10 |
| 3 | 10.53 |
| 4 | 10.03 |
| 5 | 9.59 |
| 6 | 9.20 |
| 8 | 8.55 |
| 10 | 8.05 |
| 12 | 7.64 |

Read the table as: the wider you make the corner, the narrower the street may
be. A sharp corner needs a 12.49 m street, which is not a tight city street.

## 3. Decision on D27: widen the intersection, not the street

Phase 2 widens intersection fillets and keeps street widths tight. Fixing the
off-tracking number itself is not on the table: 1.2 m off-tracking would require
a kingpin-to-bogie distance under 5.9 m on a 15 m circle (D27), which contradicts
the pinned 53 ft trailer. The gameplay answer is that a semi turns corners by
using the intersection throat, and the graph says which corners it can use.

Consequences that are gameplay, not apology:

1. A 90 degree turn on a tight street is only legal when the fillet is large
   enough. Below that, the route is invalid and the route generator must not
   produce it.
2. Delivery destinations must sit on a street whose width and fillet pass the
   rule for the turn the driver has to make to reach them.
3. The tight-street challenge S5 is a turn that passes the rule with the
   smallest available margin, so it is hard without being impossible.

## 4. Pinned street classes

| Class | Curb-to-curb width | Inner fillet | W_min from the rule | Margin |
|---|---|---|---|---|
| `arterial` | 14.0 m | 8.0 m | 8.55 m | +5.45 m |
| `local` | 11.0 m | 6.0 m | 9.20 m | +1.80 m |
| `tight` | 9.0 m | 9.0 m | 8.28 m | +0.72 m |
| `alley` | 8.0 m | straight only | not turnable | straight running only |

`alley` keeps the Phase 1 alley numbers exactly: 8.00 m wide, 60.0 m long. The
alley is legal because it is straight. An 8.0 m alley with a 90 degree corner
would need 12.49 m of width, so alleys never turn in this game.

Lane widths inside a class: 3.50 m per travel lane on arterials, 3.25 m on
locals, 3.00 m on tight streets. The remainder is parking lane and sidewalk,
which are geometry and collision, not drivable surface.

## 5. Block grid

| Profile | Block size | Street mix | Notes |
|---|---|---|---|
| `city_core` | 120 m x 100 m | arterial grid with tight alleys through the block | the single big city |
| `city_docks` | 120 m x 140 m | arterial, wide fillets, dock aprons on one edge | reuses the Phase 1 dock slot pitch: 5 slots, 4.0 m wide, centers 10.0 m apart |
| `town` | 160 m x 160 m | one arterial through, locals crossing | 3 towns, same graph code, different profile |
| `farm` | 300 m approach | single `route` edge, no grid | farm approach for S7 |

Same `RoadGraph` code builds all four profiles. Only the profile data changes.

## 6. Scene and instancing policy

- The city is its own scene (`scenes/world/city.tscn`). The test yard stays a
  separate scene and stays cheap. The city is not streamed in Phase 2: a
  block-grid city at the profile sizes above fits one scene, and streaming would
  add a determinism variable to the golden test for no measured benefit.
- Repeated props (streetlights, parked cars, docks, fences, farm buildings)
  are `MultiMesh3D`. One draw call per prop type per scene.
- LOD policy in Phase 2 is one level plus culling: props beyond 150 m are not
  instanced at all rather than swapped, because llvmpipe cost is dominated by
  triangles actually rasterised.

## 7. Render budget

Gate G3 is measured. Baseline is `docs/evidence/phase1/fps_yard.txt`: one truck in
the yard on llvmpipe at 1280x720 costs 5.05 ms mean, 4.76 ms p50, 6.25 ms p95 per
frame, with 29 visible `MeshInstance3D` and 28 collision objects, while holding
120.13 physics ticks per second.

1. City budget: the city drive must hold a mean frame time at or below the yard
   p95, 6.25 ms, on the same 60 s drive shape and the same 1280x720 llvmpipe
   context. That is the number A22 compares against, not a number copied from a
   spec.
2. Draw-call budget for the city: 80 total, of which the yard already spends 29,
   so props and road slabs must fit inside 51 draw calls. That is what forces
   `MultiMesh3D` instancing in section 6 rather than one node per prop.
3. Floor is the Phase 1 contract floor: 30 fps at 1280x720 on llvmpipe, target
   60 fps. The measured yard sits far above both, so the binding limit is the
   city scene size, not the truck.

## 8. What is not decided here

- Traffic agent budget: decided in M3 before agents are built, from a measured
  tick-rate test.
- Triangle and draw-call numbers: draw calls are capped at 80 total with the yard
  spending 29. The triangle count still has to be measured on the city scene,
  because Godot 4.7 `PrimitiveMesh` exposes no surface array length and the yard
  is built from primitive meshes.
- Whether the city reuses Phase 1 Kenney CC0 props or vendors new CC0 props:
  decided at M1c, and whatever lands goes in `docs/ATTRIBUTION.md`.
