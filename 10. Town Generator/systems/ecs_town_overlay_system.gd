class_name EcsTownOverlaySystem
extends EcsSystem

## Hands the overlay every building's footprint, whether it is closed, and its rooms, when buildings
## come or go or one changes (`building_revision`); idle buildings cost nothing.

var _overlay: EcsTownOverlay
var _view: EcsView
var _revision: int = -1

func _init(overlay: EcsTownOverlay) -> void:
	_overlay = overlay

func label() -> StringName:
	return &"overlay"

func run(world: EcsWorld, _delta: float) -> void:
	var grid := world.get_singleton(EcsTownGridSingleton) as EcsTownGridSingleton
	var buildings := world.view([EcsBuildingComponent])
	var revision := grid.building_revision if grid != null else 0
	if _overlay == null or (buildings == _view and revision == _revision):
		return
	_view = buildings
	_revision = revision
	var rects: Array[Rect2i] = []
	var closed: Array[bool] = []
	var rooms: Array = []
	for building in buildings.column(EcsBuildingComponent):
		rects.append((building as EcsBuildingComponent).footprint)
		closed.append((building as EcsBuildingComponent).closed)
		rooms.append_array((building as EcsBuildingComponent).rooms)
	_overlay.footprints = rects
	_overlay.closed = closed
	_overlay.rooms = rooms
	_overlay.queue_redraw()
