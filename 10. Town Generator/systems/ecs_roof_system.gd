class_name EcsRoofSystem
extends EcsSystem

## The only writer of `roof`. For each building whose rooms changed, roofs every enclosed
## region — room or sealed — and the building's walls and doors around it, and clears the
## rest of its footprint.

var _catalog: EcsTownCatalog

func _init(catalog: EcsTownCatalog) -> void:
	_catalog = catalog

func label() -> StringName:
	return &"roof"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	if grid == null or grid.dirty_roofs.is_empty():
		return
	_catalog.number()
	var roof_id: int = _catalog.roofs[0].id if not _catalog.roofs.is_empty() else 0
	for id: int in grid.dirty_roofs:
		var building := world.get_component(id, EcsBuildingComponent) as EcsBuildingComponent
		if building == null:
			continue
		var rect := building.footprint
		var covered: Dictionary = {}
		for room: Dictionary in building.rooms:
			for cell: Vector2i in room["cells"]:
				covered[cell] = true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var around := cell + Vector2i(dx, dy)
						if rect.has_point(around) \
								and grid.structure[EcsTownGrid.index(grid, around)] != EcsTownGridSingleton.NONE:
							covered[around] = true
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var i := y * grid.width + x
				var want := roof_id if covered.has(Vector2i(x, y)) else 0
				if grid.roof[i] != want:
					grid.roof[i] = want
					grid.dirty[i] = int(grid.dirty.get(i, 0)) | EcsTownGridSingleton.CHANGED_ROOF
	grid.dirty_roofs.clear()
