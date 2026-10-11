# CITYHAUL Controls

## Keyboard

| Key | Action |
|---|---|
| W | Throttle |
| S | Brake |
| Shift | Clutch |
| A / D or Left / Right | Steer |
| 1..0 | Gear keys (1..5 high range, 6..0 low range) |
| R | Reverse |
| N | Neutral |
| E | Range toggle |
| Z | Retarder up |
| X | Retarder down |
| Space | Parking brake |
| U | Coupler unlock |
| L | Landing gear |
| Tab | Camera cycle (Chase -> Cab -> Trailer -> Free) |
| G | Trailer path overlay |
| V | Transmission mode (auto/manual) |
| F3 | Debug overlay |
| F1 | Context help |
| Esc | Pause menu |

## Gamepad

| Control | Action |
|---|---|
| LT | Throttle |
| RT | Brake |
| LSx | Steer |
| LB | Clutch |
| A | Gear up |
| B | Gear down |
| X | Range |
| Y | Parking brake |
| Dpad left / right | Retarder |
| Dpad up / down | Landing gear |
| RS | Camera |
| RB | Camera cycle |
| Start | Pause |

## No-op rules (all show a HUD reason flash)

- Gear change without clutch or automatic mode.
- R above 0.5 m/s.
- Retarder in low range, above gear 4, or below 15 km/h.
- U while moving.
- L while attached or moving.

## Cameras

Tab cycles Chase -> Cab -> Trailer -> Free.

- Chase: spring arm 14 m behind and 5 m above the tractor ref, damping 0.25 s,
  pitch -45 deg.
- Cab: camera at cab eye (cab-local (0.35, 1.15, -0.20)), mouse look limited
  to +/- 30 deg yaw and -10..+20 deg pitch; cab steering wheel mesh rotates
  with the 2.5-turn ratio.
- Trailer: spring arm 12 m behind the trailer ref.
- Free: orbit, 20 m radius around the tractor ref, right stick or mouse drag.
- Mirrors: 2 `SubViewport` cameras at 480 x 270 rendered onto cab mirror quads,
  active only in Cab mode (CPU budget).

## Trailer path overlay (G)

Dashed predicted trailer path, 30 m long, from the current articulation and
steer angle, recomputed every 0.25 s. Training aid for the core mechanic.
