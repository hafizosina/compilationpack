class_name EcsSettlementRoleDef
extends Resource

## One kind of building a town may have: what it is built as, the smallest town it appears in,
## what must be within reach for it, and how many it houses and feeds.

@export var key: StringName = &""
@export var display_name: String = ""
## The module 10 building type it is built as (step 6 adds the ones missing).
@export var building: StringName = &"house"
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
## Rings its yard may grow; 0 takes the settlement's.
@export var yard_depth: int = 0
