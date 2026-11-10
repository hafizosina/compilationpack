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
