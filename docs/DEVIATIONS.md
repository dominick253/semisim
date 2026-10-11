# CITYHAUL Deviations Log

Every spec item that is technically impossible on this engine or host, with
field, spec value, final value, and reason. Never silently substitute.

| Field | Spec value | Final value | Reason |
|---|---|---|---|
| T1 expected Fy at alpha 0.05 rad | 28,100 N | 22,226 N (asserted with the spec's +/- 10 percent band) | The spec's own formula Fy = D*sin(C*atan(B*alpha)), B=10, C=1.6, D=1.10*29,905 N evaluates to 22,226 N. 28,100 N is not reachable from the pinned constants; the formula is authoritative. |
| T5 assertion quantity | "wheel force 69,600 N" | 69,920 Nm wheel torque (asserted with the spec's +/- 8 percent band) | 2230 x 9.015 x 3.70 x 0.94 is a torque product in Nm, not a force. Dividing by the 0.563 m rolling radius would give 124,191 N, which matches no spec number. The spec number 69,600 matches the torque 69,920 Nm within 0.5 percent, so the unit label in the spec is a typo. |

