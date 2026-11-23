class_name EcsSettlementRoleDef
extends Resource

## One kind of building a town may have: what it is built as, when the census asks for it, who works
## and lives in it, and where its plot likes to stand.

@export var key: StringName = &""
@export var display_name: String = ""
## The module 10 building type it is built as; empty for an outdoor work with no walls (step 7).
@export var building: StringName = &"house"
## An outdoor work's layout rule (EcsOutdoorBuilder); empty takes its key.
@export var layout: StringName = &""
## Its rooms' roles, largest first, in place of the building type's; empty keeps the type's.
@export var rooms: Array[StringName] = []
## Its wealth when nobody owns it: 0 poor, 1 middling, 2 rich; -1 takes it from where it stands.
@export_range(-1, 2) var wealth: int = -1
## The smallest and largest tier it appears in: 0 hamlet, 1 village, 2 town, 3 city, 4 great city.
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var min_tier: int = 0
@export_enum("Hamlet", "Village", "Town", "City", "Great City") var max_tier: int = 4
## Survey facts that must all be present, and facts of which one must be (EcsResourceSurvey keys).
@export var requires: Array[StringName] = []
@export var requires_any: Array[StringName] = []
## Survey facts that must be absent.
@export var absent: Array[StringName] = []
## Its group, for quarters and the viewer's tint: home, elite, faith, trade, food, entertainment,
## craft, works or farming.
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
## What it has beside it: &"field", &"pen", &"dock", or empty for nothing.
@export var annex: StringName = &""
## A field's or pen's smallest and largest size, in L1 cells.
@export var annex_min: Vector2i = Vector2i.ZERO
@export var annex_max: Vector2i = Vector2i.ZERO
## Rings its yard may grow; 0 takes the settlement's.
@export var yard_depth: int = 0

@export_group("Census")
## The resource it makes (EcsResourceDef key) and how much one of it makes a year.
@export var makes: StringName = &""
@export var output: float = 0.0
## The survey fact that limits how many there can be, and how many at that fact's full score in a
## hamlet's catchment; empty fact for no limit.
@export var capacity_fact: StringName = &""
@export var capacity: float = 0.0
## Service: one per this many people (travellers counted); 0 when it isn't one.
@export var per_people: int = 0
## A fixed count every town it is allowed in has; 0 for none.
@export var per_town: int = 0
## Chain: one per this many of the role `serves`.
@export var serves: StringName = &""
@export var per_served: int = 0
## Traffic level it needs (0 quiet … 3 crossroads); -1 when traffic doesn't make it. With
## `travellers_per`, one per that many travellers staying the night.
@export_range(-1, 3) var traffic_min: int = -1
@export var travellers_per: int = 0
## Workers it takes. A role with any has an owner family.
@export var places: int = 0
## The owner family's chances of being poor, middling and rich.
@export var wealth_odds: Vector3 = Vector3(0.6, 0.35, 0.05)
## The owner family lives in it (unless rich: a rich family always has its own house).
@export var lives_at_work: bool = false
## The chance its owner sells from home (a shop front on the lane) rather than at the market.
@export_range(0.0, 1.0) var sells_at_home: float = 0.0
## A stockpile it keeps in its yard by the lane, for heavy goods sold where they are made.
@export var stockpile: StringName = &""
## Built as a walled compound: a fence and gate, the main house across the back, a pavilion and a
## kitchen house in front.
@export var compound: bool = false
## A house for families of this wealth (0 poor, 1 middling, 2 rich, 3 the village head); -1 when it
## isn't a house.
@export_range(-1, 3) var home: int = -1
