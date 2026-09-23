extends Node2D

## Headless acceptance test for the lifecycle refactor — EcsEntityManager owning
## spawn and kill, EcsNodeSyncSystem owning the per-tick mirror.
##
## It exists because the refactor's own handoff proposed re-running the Step-2
## combat acceptance test as proof that behaviour was undisturbed, and that test
## went out of the tree with the combat layer at d50aaf9. This covers the thing
## most likely to have broken instead: node lifetime used to be *inferred* from
## a query, and is now *commanded*, so the cases where an entity stops matching
## without dying are exactly where the two models diverge.
##
## Run it:
##   GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
##   "$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn"
##
## Exit code is 0 only if every check passed.
##
## Every tick awaits a physics frame. Overlaps resolve on the physics server's
## schedule, not the instant a body is moved, so a test that did its work
## synchronously would read an empty overlap list and blame Area2D for it.

const TICK: float = 1.0 / 60.0

var _world: EcsWorld
var _scheduler: EcsScheduler
var _manager: EcsEntityManager
var _catalog: EcsEntityCatalog
var _entities: Node2D
var _checks: int = 0
var _failures: int = 0

func _ready() -> void:
	_catalog = load("res://9. EcsSystem/defs/catalog.tres") as EcsEntityCatalog
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)

	_manager = EcsEntityManager.new(_entities)
	_world = EcsWorld.new()
	_world.add_singleton(EcsLifecycleComponent.new())

	# No brain, no movement: nothing wanders, so every position in this test is
	# one the test put there or one collision corrected. The stages that are
	# here are the ones the refactor touched.
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSpawnerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	await _run()

	print("[test] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _run() -> void:
	await _spawn_builds_declared_nodes()
	await _pickup_hides_the_sprite_without_freeing_it()
	await _putting_it_back_shows_it_again()
	await _a_body_with_no_position_stands_down()
	await _kill_takes_the_data_and_the_nodes()
	await _a_spawner_note_is_fulfilled_next_tick()
	await _collision_still_separates_manager_owned_bodies()
	await _it_sees_before_it_takes()
	await _an_immovable_body_is_not_shoved_around()
	await _a_ground_item_is_walked_over_not_bumped_into()
	await _it_walks_to_what_it_sees_and_takes_it()
	await _a_trip_it_cannot_finish_is_given_up_on()

## A component's `const NODE_KIND` is what gets it a node, so a berry — sprite,
## no shape — must come out with a sprite and no body. And everything an entity
## owns must hang under that entity's own container.
func _spawn_builds_declared_nodes() -> void:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(50.0, 0.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(60.0, 0.0))
	await _tick(1)

	var box := _manager.container_for(rabbit)
	var view := _manager.node_for(rabbit, EcsConst.NODE_SPRITE)
	var body := _manager.node_for(rabbit, EcsConst.NODE_BODY)
	_check("rabbit gets a container named for it",
		box != null and box.name == "entity_%d" % rabbit)
	_check("the container hangs under Entities", box != null and box.get_parent() == _entities)
	_check("rabbit gets a sprite", view != null)
	_check("rabbit gets a body", body != null)
	_check("both hang under the entity's own container",
		view != null and body != null and view.get_parent() == box and body.get_parent() == box)
	_check("children are named by node kind",
		view != null and view.name == EcsConst.NODE_SPRITE
		and body != null and body.name == EcsConst.NODE_BODY)
	_check("the container carries the transform, children sit at local zero",
		box != null and box.position.is_equal_approx(Vector2(50.0, 0.0))
		and view != null and view.position.is_equal_approx(Vector2.ZERO)
		and body != null and body.position.is_equal_approx(Vector2.ZERO))
	_check("the body is therefore where the entity is",
		body != null and body.global_position.is_equal_approx(Vector2(50.0, 0.0)))
	_check("berry gets a sprite", _manager.node_for(berry, EcsConst.NODE_SPRITE) != null)
	_check("berry gets a body, so it can be seen and touched",
		_manager.node_for(berry, EcsConst.NODE_BODY) != null)
	_check("berry declares no sensor or action, so it has neither",
		_manager.node_for(berry, EcsConst.NODE_SENSOR) == null
		and _manager.node_for(berry, EcsConst.NODE_ACTION) == null)
	_check("a forager declares all four",
		_manager.node_for(rabbit, EcsConst.NODE_SENSOR) != null
		and _manager.node_for(rabbit, EcsConst.NODE_ACTION) != null)
	# The layer policy is declared on the components, so these assert that the
	# manager built what EcsShape/Sensor/ActionComponent asked for.
	var sensor_area := _manager.node_for(rabbit, EcsConst.NODE_SENSOR) as Area2D
	var action_area := _manager.node_for(rabbit, EcsConst.NODE_ACTION) as Area2D
	var body_area := body as Area2D
	_check("only bodies occupy a layer",
		body_area.collision_layer == EcsConst.LAYER_BODY
		and sensor_area.collision_layer == EcsConst.LAYER_NONE
		and action_area.collision_layer == EcsConst.LAYER_NONE)
	_check("so nothing can detect a sensor or an action area",
		body_area.monitorable and not sensor_area.monitorable
		and not action_area.monitorable)
	_check("sensor and action look for bodies and nothing else",
		sensor_area.collision_mask == EcsConst.LAYER_BODY
		and action_area.collision_mask == EcsConst.LAYER_BODY)

## The regression this whole refactor risks. Picking a berry up removes its
## EcsPositionComponent — it is alive, it is simply not anywhere. Under the old
## render system that freed the Sprite2D as a side effect of the query. Under
## the manager the node must survive and merely stop being drawn.
func _pickup_hides_the_sprite_without_freeing_it() -> void:
	var rabbit := _first_of(&"rabbit")
	var berry := _first_of(&"berry")
	await _tick(2)

	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	var view := _manager.node_for(berry, EcsConst.NODE_SPRITE) as Sprite2D
	var box := _manager.container_for(berry)
	_check("the berry was picked up", bag != null and bag.items.has(berry))
	_check("the berry lost its position", not _world.has(berry, EcsPositionComponent))
	_check("the berry is still alive", _world.is_alive(berry))
	_check("its nodes were NOT freed", view != null and is_instance_valid(view))
	_check("its container is hidden instead", box != null and not box.visible)
	_check("so the sprite under it is not drawn", view != null and not view.is_visible_in_tree())

## And the inverse, which the old model could not express at all: put it back
## down and it is drawn again, with no node rebuilt.
func _putting_it_back_shows_it_again() -> void:
	var berry := _first_of(&"berry")
	var before := _manager.node_for(berry, EcsConst.NODE_SPRITE)
	var place := EcsPositionComponent.new()
	place.position = Vector2(400.0, 400.0)
	_world.add(berry, place)
	await _tick(1)

	var view := _manager.node_for(berry, EcsConst.NODE_SPRITE) as Sprite2D
	var box := _manager.container_for(berry)
	_check("dropping it makes it visible again", view != null and view.is_visible_in_tree())
	_check("it is the same node, not a new one", view == before)
	_check("the container followed the new position",
		box != null and box.position.is_equal_approx(Vector2(400.0, 400.0)))

## Same rule one layer down: an entity that is not anywhere must not collide
## from wherever it last stood.
func _a_body_with_no_position_stands_down() -> void:
	var rabbit := _first_of(&"rabbit")
	var body := _manager.node_for(rabbit, EcsConst.NODE_BODY) as Area2D
	var held := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent

	_world.remove(rabbit, EcsPositionComponent)
	await _tick(1)
	_check("a body with no position stops monitoring", body != null and not body.monitoring)

	_world.add(rabbit, held)
	await _tick(1)
	_check("and starts again when the position returns", body != null and body.monitoring)

## Kill is the only thing that takes nodes away.
func _kill_takes_the_data_and_the_nodes() -> void:
	var berry := _first_of(&"berry")
	var containers_before := _entities.get_child_count()
	var inbox := _world.get_singleton(EcsLifecycleComponent) as EcsLifecycleComponent
	inbox.kill_requests.append(berry)
	await _tick(1)

	_check("the killed entity is gone from the world", not _world.is_alive(berry))
	_check("its nodes are gone from the manager",
		_manager.node_for(berry, EcsConst.NODE_SPRITE) == null
		and _manager.container_for(berry) == null)
	_check("one container freed takes the whole entity with it",
		_entities.get_child_count() == containers_before - 1)

## The spawner no longer builds anything itself. It leaves a note and the
## lifecycle stage fulfils it at the top of the next tick — one tick later, and
## the spawner picks the id back off its own note.
func _a_spawner_note_is_fulfilled_next_tick() -> void:
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", Vector2(-800.0, -400.0))
	var spawner := _world.get_component(bush, EcsSpawnerComponent) as EcsSpawnerComponent

	await _tick(1)
	_check("the spawner has a note in flight", spawner.pending.size() == 1)
	_check("and nothing has been built for it yet", spawner.spawned.is_empty())

	await _tick(1)
	_check("the note is fulfilled on the next tick", spawner.pending.is_empty())
	_check("and the spawner harvested the id", spawner.spawned.size() == 1)
	var born: int = spawner.spawned[0] if spawner.spawned.size() == 1 else EcsWorld.NO_ENTITY
	_check("the spawned entity got its sprite",
		_manager.node_for(born, EcsConst.NODE_SPRITE) != null)

## The behaviour that had to survive all of the above: soft collision reading
## overlaps off bodies it no longer creates.
func _collision_still_separates_manager_owned_bodies() -> void:
	var a := _manager.spawn(_world, _catalog, &"rabbit", Vector2(1000.0, 0.0))
	var b := _manager.spawn(_world, _catalog, &"rabbit", Vector2(1002.0, 0.0))
	# Nothing writes the areas' positions any more — they ride their containers,
	# which EcsNodeSyncSystem moves. If that wiring were wrong the broadphase
	# would see two bodies stacked at the origin and this would not separate.
	var pa := _world.get_component(a, EcsPositionComponent) as EcsPositionComponent
	var pb := _world.get_component(b, EcsPositionComponent) as EcsPositionComponent
	var started := pa.position.distance_to(pb.position)

	await _tick(40)

	var ended := pa.position.distance_to(pb.position)
	var touching := _radius_of(a) + _radius_of(b)
	_check("two stacked bodies pushed apart (%.1f -> %.1f px, touching at %.1f)"
		% [started, ended, touching], ended > started)
	_check("and settled at least their combined radii apart", ended >= touching - 0.5)

## The chain the whole sensor/action layer exists for: a forager knows about a
## berry only if its sensor area overlaps it, and takes it only once its action
## area is touching the berry's body.
func _it_sees_before_it_takes() -> void:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(2000.0, 2000.0))
	var near := _manager.spawn(_world, _catalog, &"berry", Vector2(2000.0, 2100.0))
	var far := _manager.spawn(_world, _catalog, &"berry", Vector2(2000.0, 2900.0))
	var sensor := _world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent
	var action := _world.get_component(rabbit, EcsActionComponent) as EcsActionComponent
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	await _tick(2)

	# 100 px away: inside the 280 px sensor, outside the 34 + 14 px reach.
	_check("it sees the berry 100 px away", sensor.perceived.has(near))
	_check("it does not see the one 900 px away", not sensor.perceived.has(far))
	_check("seeing is not reaching", not action.reached.has(near))
	_check("so it has not taken it", not bag.items.has(near))

	# Bring it to arm's length without moving the rabbit.
	(_world.get_component(near, EcsPositionComponent) as EcsPositionComponent).position \
		= Vector2(2000.0, 2030.0)
	await _tick(2)

	_check("once the bodies touch the action area, it is in reach",
		action.reached.has(near))
	_check("and it is taken", bag.items.has(near))
	_check("the one it never saw is untouched",
		_world.has(far, EcsPositionComponent) and not bag.items.has(far))

## A bush is solid and has no EcsMovementComponent, so a walker must be pushed
## out of it and it must not give an inch — solidity and movability are separate
## questions and this is the pair that proves the second one.
func _an_immovable_body_is_not_shoved_around() -> void:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-2000.0, -2000.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", Vector2(-1990.0, -2000.0))
	var bush_at := _world.get_component(bush, EcsPositionComponent) as EcsPositionComponent
	var rabbit_at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var bush_started := bush_at.position
	var rabbit_started := rabbit_at.position
	# Overlapping hard: 10 px apart, bodies of 22 and 45.
	await _tick(20)

	_check("the bush did not budge", bush_at.position.is_equal_approx(bush_started))
	_check("the walker was the one pushed out",
		not rabbit_at.position.is_equal_approx(rabbit_started))

## And the other half of that split: a berry has a body so it can be seen and
## reached, but `is_solid` off, so it is walked over rather than bumped
## into. Nobody moves — not the walker, and not the thing on the ground.
##
## Its own scheduler, with no pickup in it: the rabbit taking the berry would
## end the overlap and the test would pass without proving anything.
func _a_ground_item_is_walked_over_not_bumped_into() -> void:
	var loose := EcsScheduler.new()
	loose \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-3000.0, -3000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-2990.0, -3000.0))
	var berry_at := _world.get_component(berry, EcsPositionComponent) as EcsPositionComponent
	var rabbit_at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var berry_started := berry_at.position
	var rabbit_started := rabbit_at.position
	# 10 px apart with bodies of 22 and 14: deep inside each other, and under
	# the old rule the rabbit would have been shoved 26 px clear.
	for i in 20:
		loose.run_all(_world, TICK)
		await get_tree().physics_frame

	_check("the ground item stayed where it was dropped",
		berry_at.position.is_equal_approx(berry_started))
	_check("and the walker stood right on top of it, unpushed",
		rabbit_at.position.is_equal_approx(rabbit_started))
	_check("the berry still has a body to be seen by",
		_world.has(berry, EcsBodyComponent)
		and not (_world.get_component(berry, EcsBodyComponent) as EcsBodyComponent).is_solid)

## The whole loop, driven end to end: a forager spots a berry it cannot reach,
## walks to it, and takes it the moment its action area meets the berry's body.
##
## This one runs its own scheduler, with forage and movement added, because
## every other test above deliberately has no brain and no legs so that nothing
## moves except what the test moves. `low_brain` is left out on purpose: with no
## fallback wandering, the rabbit either walks to the berry it saw or it does
## not, and the check cannot pass by accident.
func _it_walks_to_what_it_sees_and_takes_it() -> void:
	var walking := EcsScheduler.new()
	walking \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsForageSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	# Far from everything else in this file, and outside the arena the wander
	# bounds clamp to, so no other entity drifts into the experiment.
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(2000.0, -2000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(2200.0, -2000.0))
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	var at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var started := at.position

	# 200 px at 72 px/sec is a bit under 3 seconds. 240 ticks is four.
	for i in 240:
		walking.run_all(_world, TICK)
		await get_tree().physics_frame
		if bag.items.has(berry):
			break

	_check("it walked toward the berry it could see", at.position.x > started.x + 100.0)
	_check("and picked it up on arrival", bag.items.has(berry))
	_check("which is what leaving the world means", not _world.has(berry, EcsPositionComponent))
	_check("it stopped at arm's length, not on top of it",
		at.position.distance_to(Vector2(2200.0, -2000.0)) > 20.0)

## A destination it can never stand on. Soft collision holds the walker and the
## bush 67 px apart — bodies of 22 and 45 — while its arrive radius is 6, so
## walking at the middle of a bush is a trip that cannot end. Before the trip
## clock it pushed at it forever, and because `has_destination` stayed true,
## forage and low_brain both skipped it every tick: stuck for good.
##
## A bush and not a berry, now that a berry is walked over: this has to be a
## thing that really does block, or the test proves nothing.
func _a_trip_it_cannot_finish_is_given_up_on() -> void:
	var blocked := EcsScheduler.new()
	blocked \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(2000.0, 2000.0))
	var bush_at := Vector2(2160.0, 2000.0)
	_manager.spawn(_world, _catalog, &"berry_bush", bush_at)
	var at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var move := _world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent
	var started := at.position

	# Tightened from the blueprint's defaults so the test is 3 seconds and not
	# 8. 160 px at 72 px/sec is 2.2 sec of trip, so the budget is about 2.7.
	move.timeout_slack = 1.0
	move.timeout_grace = 0.5
	move.destination = bush_at
	move.has_destination = true

	var ticks := 0
	for i in 240:
		blocked.run_all(_world, TICK)
		await get_tree().physics_frame
		ticks += 1
		if not move.has_destination:
			break

	_check("it walked at the bush it could not stand in", at.position.x > started.x + 20.0)
	_check("and was still held short of it", at.position.distance_to(bush_at) > move.arrive_radius)
	_check("the trip timed out instead of pushing forever", not move.has_destination)
	_check("it ran roughly the budget it was priced, not the whole loop",
		ticks > 80 and ticks < 220)
	_check("and the clock is back to zero for the next trip",
		is_zero_approx(move.time_left))

func _tick(count: int) -> void:
	for i in count:
		_scheduler.run_all(_world, TICK)
		await get_tree().physics_frame

func _first_of(type_id: StringName) -> int:
	for id in _world.query([EcsNameComponent]):
		if (_world.get_component(id, EcsNameComponent) as EcsNameComponent).type_id == type_id:
			return id
	return EcsWorld.NO_ENTITY

func _radius_of(id: int) -> float:
	return (_world.get_component(id, EcsBodyComponent) as EcsBodyComponent).radius

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[test] %s  %s" % ["PASS" if passed else "FAIL", what])
