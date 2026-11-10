class_name EcsSettlementSite
extends RefCounted

## Where a town stands and its centre: what EcsSitePicker found. L1 cells are whole-region L1 cells.

## The region cell picked.
var l2_cell: Vector2i = Vector2i.ZERO
## The town's L1 area, centred on the site and inside the region.
var area: Rect2i = Rect2i()
## The plaza, in L1 cells, and the well in its middle.
var plaza: Rect2i = Rect2i()
var well: Vector2i = Vector2i.ZERO
## The plaza floor, the well and the road floors, as build commands on L1 cells.
var commands: Array[EcsBuildCommand] = []
## L1 rects no resource node may stand in.
var cleared: Array[Rect2i] = []
## The site's score and its parts: {water, open, room, river, total}.
var score: Dictionary = {}
## Main roads and lanes: [{kind: &"main" or &"lane", points: L1 polyline, l2_points (main only), width}].
var roads: Array[Dictionary] = []
## Where the main roads leave the region, in region cells.
var exits: Array[Vector2i] = []
## Road cells: L1 cell -> &"main", &"lane" or &"bridge".
var road_cells: Dictionary = {}
## Single L1 cells no resource node may stand on (roads and their verges), beside `cleared`.
var cleared_cells: Dictionary = {}
## Water crossings on the main roads.
var bridges: int = 0
## Route cost from the site to every region cell over the def's road costs (EcsRoadPlanner's).
var costs: PackedFloat32Array = PackedFloat32Array()
## What is within reach (EcsResourceSurvey), and what the town is and has (EcsTownEconomy).
var survey: Dictionary = {}
var economy: Dictionary = {}
## Plots: [{footprint: Rect2i, front: the side the door faces, door: L1 cell, yard: L1 cells}].
var plots: Array[Dictionary] = []
## L1 cell -> index into `plots`, for footprints and yards.
var plot_at: Dictionary = {}
