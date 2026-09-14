class_name EcsSpawnerSystem
extends EcsSystem

## Runs every spawner's clock and puts new entities into the world.
##
## It is the only system that creates entities, and it runs first, so anything
## born this tick is decided for, moved, collided, drawn and reported in the
## same tick it appears — no one-frame gap where a berry exists but is invisible.
##
## Spawning mid-iteration is safe because `world.query()` returns a snapshot
## array rather than a live cursor: the new ids simply are not in the list this
## system is walking, and get picked up by every system after it.
##
## The factory and catalog arrive through `_init` rather than being looked up.
## Module 8's spawner searched the scene tree for its factory by group, which
## works but means the component can fail at runtime if the factory is missing.
## Here the dependency is visible in main.gd's pipeline and cannot go absent.

var _factory: EcsEntityFactory
var _catalog: EcsEntityCatalog

func _init(factory: EcsEntityFactory, catalog: EcsEntityCatalog) -> void:
	_factory = factory
	_catalog = catalog

func label() -> StringName:
	return &"spawner"

func run(world: EcsWorld, delta: float) -> void:
	if _factory == null or _catalog == null:
		return
	for id in world.query([EcsPositionComponent, EcsSpawnerComponent]):
		var spawner := world.get_component(id, EcsSpawnerComponent) as EcsSpawnerComponent
		spawner.cooldown -= delta
		if spawner.cooldown > 0.0:
			continue
		spawner.cooldown = spawner.interval

		# Prune first, so anything harvested since last tick frees its slot.
		# Still on the ground means alive AND still carrying a position.
		var still_loose: Array[int] = []
		for child in spawner.spawned:
			if world.is_alive(child) and world.has(child, EcsPositionComponent):
				still_loose.append(child)
		spawner.spawned = still_loose
		if still_loose.size() >= spawner.max_loose:
			continue

		var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		var born := _factory.spawn(world, _catalog, spawner.spawns,
			EcsConst.random_point_near(here.position, spawner.radius))
		if born != EcsWorld.NO_ENTITY:
			spawner.spawned.append(born)
