class_name WorldConstants
## Pinned world numbers for Phase 2. The decisions and the measurement behind
## each one are in docs/world-spec.md. Physics values never go here, and world
## values never go in PHYSICS_CONSTANTS.

# Clearance allowance added on top of the body width and the measured kingpin
# plate drift. See TurnEnvelope and DEVIATIONS D41.
const HANDLING_MARGIN_M: float = 0.50

# Curb to curb widths and inner corner fillets, pinned as a pair. A street class
# is only legal if the pair satisfies TurnEnvelope.turn_fits.
const STREET_WIDTH_M: Dictionary = {
	"arterial": 14.0,
	"local": 11.0,
	"tight": 9.0,
	"alley": 8.0,
}

const CORNER_FILLET_M: Dictionary = {
	"arterial": 8.0,
	"local": 6.0,
	"tight": 9.0,
	"alley": 0.0,
}

const LANE_WIDTH_M: Dictionary = {
	"arterial": 3.50,
	"local": 3.25,
	"tight": 3.00,
	"alley": 0.0,
}

# City core block grid: 8 by 6 blocks, so 9 by 7 intersections.
const CITY_COLS: int = 9
const CITY_ROWS: int = 7
const CITY_BLOCK_W_M: float = 120.0
const CITY_BLOCK_H_M: float = 100.0

# Streets repeat arterial, local, tight along each axis so every class is
# present in the grid and the tight streets are the ones the challenge S5 uses.
const ARTERIAL_EVERY_N: int = 3

# Towns and farms: same graph code, different block profile.
const TOWN_PROFILES: PackedStringArray = ["northfield", "ridgemill", "sandhollow"]
const TOWN_COLS: int = 5
const TOWN_ROWS: int = 4
const TOWN_BLOCK_W_M: float = 160.0
const TOWN_BLOCK_H_M: float = 160.0
const FARM_APPROACH_M: float = 300.0

# Instancing and culling policy. Props beyond this distance are not instanced
# at all rather than swapped, because llvmpipe cost is dominated by triangles
# that are actually rasterised.
const PROP_CULL_DISTANCE_M: float = 150.0
const MAX_CONVEX_PIECES_PER_BODY: int = 16

# Traffic agent budget and headway are pinned in M3 from a measured tick rate,
# not here, because an agent budget chosen before measuring is a guess.
