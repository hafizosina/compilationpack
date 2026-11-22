class_name EcsSettlementRoleDef
extends Resource

## One kind of building a town may have: what it is built as, the smallest town it appears in,
## what must be within reach for it, and how many it houses and feeds.

@export var key: StringName = &""
@export var display_name: String = ""
## The module 10 building type it is built as; empty for an outdoor work with no walls (step 7).
@export var building: StringName = &"house"
## Its rooms' roles, largest first, in place of the building type's; empty keeps the type's.
@export var rooms: Array[StringName] = []
## Its wealth: 0 poor, 1 middling, 2 rich; -1 takes it from where it stands (rich by the plaza).
@export_range(-1, 2) var wealth: int = -1
## The smallest tier it appears in: 0 hamlet, 1 village, 2 town, 3 city, 4 great city.
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var min_tier: int = 0
## Survey facts that must all be present, and facts of which one must be (EcsResourceSurvey keys).
@export var requires: Array[StringName] = []
@export var requires_any: Array[StringName] = []
## Survey facts that must be absent: a windmill only where no river turns a watermill.
@export var absent: Array[StringName] = []
## People living in one.
@export var residents: int = 0
## People one feeds.
@export var feeds: int = 0
## Its group, for the viewer's tint: home, food, craft, faith, trade, water or works.
@export var group: StringName = &"home"
## Its footprint's smallest and largest width and height, in L1 cells.
@export var size_min: Vector2i = Vector2i(6, 5)
@export var size_max: Vector2i = Vector2i(8, 7)
## Placing order, highest first.
@export var priority: int = 10
## Site rule -> weight (EcsPlotPlanner.RULES); its score at a spot is the weighted sum.
@export var sites: Dictionary[StringName, float] = {}
## Rules that must all score at least 0.5 at its spot, and rules of which one must.
@export var must: Array[StringName] = []
@export var must_any: Array[StringName] = []
## What it has beside it: &"field" (a farmhouse), &"pen" (a herder, barn or stable), &"dock" (by
## water), or empty for nothing.
@export var annex: StringName = &""
## A field's or pen's smallest and largest size, in L1 cells.
@export var annex_min: Vector2i = Vector2i.ZERO
@export var annex_max: Vector2i = Vector2i.ZERO
## Rings its yard may grow; 0 takes the settlement's.
@export var yard_depth: int = 0
