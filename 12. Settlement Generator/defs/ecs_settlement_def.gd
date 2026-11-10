class_name EcsSettlementDef
extends Resource

## A kind of settlement, a tier of town: its L1 area, plaza, site, roads, economy and plots. What the
## land under it is comes from the region's EcsLandDef.

@export var key: StringName = &""
@export var display_name: String = ""
## The town's area in L1 cells.
@export var size: Vector2i = Vector2i(160, 120)

@export_group("Town")
## The plaza at the town's centre, in L1 cells, its floor, and the well in its middle.
@export var plaza_size: Vector2i = Vector2i(12, 12)
@export var plaza_floor: StringName = &"stone"
@export var well: StringName = &"well"
## Cells round the plaza kept free of nodes.
@export var clear_margin: int = 2
@export_group("Site")
## Water this far from the site, in region cells, scores full marks; nearer or further scores less.
@export var water_near: Vector2i = Vector2i(2, 10)
@export var water_weight: float = 1.0
## Open grass and sand round the site.
@export var open_weight: float = 1.0
## Region cells kept between the town's area and the region's edge.
@export var edge_margin_cells: int = 4
@export_group("Roads")
## How many main roads leave the town for the region's edge, picked in this range.
@export var exits: Vector2i = Vector2i(2, 4)
## Road widths in L1 cells.
@export var main_width: int = 2
@export var lane_width: int = 1
## The floor of a road, and of a road over water: a bridge.
@export var road_floor: StringName = &"road"
@export var bridge_floor: StringName = &"wood"
## What a step onto each kind of ground costs a route, in EcsTerrainGenerator's kind order: grass,
## water, sand, rock, forest. Water's is high, so a bridge is built only when going round is far longer.
@export var road_costs: PackedFloat32Array = PackedFloat32Array([1.0, 30.0, 1.2, 4.0, 3.0])
## A step onto a road already routed costs this share, so main roads share a trunk before forking.
@export var reuse_cost: float = 0.3
## Node-free cells kept beside main roads.
@export var verge: int = 1
## Most bridges a town's roads may have.
@export var max_bridges: int = 3
@export_group("Economy")
## How big a settlement it is: what roles it may have and how much of its trade it builds.
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var tier: int = 0
## How far its people walk for what they live on, as a route cost over `road_costs` (grass 1 a region cell).
@export var catchment: float = 40.0
## Role key -> count range every settlement of this tier has.
@export var base_roles: Dictionary[StringName, Vector2i] = {}
## The main trade's core counts are multiplied by this.
@export var trade_scale: float = 1.0
@export_group("Plots")
## A field's ground and what grows on it, in rows with a path between.
@export var field_terrain: StringName = &"dirt"
@export var field_crop: StringName = &"crop"
## Cells kept between footprints, so a lane fits.
@export var plot_gap: int = 2
## Rings a yard may grow round its footprint.
@export var yard_depth: int = 4
## The dearest route a lane may take from a door to a road; a plot further out is dropped.
@export var lane_reach: float = 250.0
