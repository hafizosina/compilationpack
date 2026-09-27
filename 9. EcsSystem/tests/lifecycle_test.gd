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
var _uids: Dictionary = {}  # entity id -> uid, for asking after a record once it dies

func _ready() -> void:
	_catalog = load("res://9. EcsSystem/defs/catalog.tres") as EcsEntityCatalog
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)

	_manager = EcsEntityManager.new(_entities)
	_world = EcsWorld.new()
	_world.add_singleton(EcsLifecycleSingleton.new())

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
	await _flags_share_one_inspector_tab()
	await _pickup_keeps_a_record_and_ends_the_berry()
	await _kill_takes_the_data_and_the_nodes()
	await _a_spawner_note_is_fulfilled_next_tick()
	await _collision_still_separates_manager_owned_bodies()
	await _it_sees_before_it_takes()
	await _an_immovable_body_is_not_shoved_around()
	await _a_ground_item_is_walked_over_not_bumped_into()
	await _it_walks_to_what_it_sees_and_takes_it()
	await _a_trip_it_cannot_finish_is_given_up_on()
	await _a_stolen_target_is_dropped_the_tick_it_vanishes()
	await _hunger_climbs_and_gates_the_food_rung()
	await _eating_empties_the_bag_and_ends_the_berry()
	await _starving_costs_health_and_then_the_entity()
	await _being_well_fed_mends_and_the_band_between_does_neither()
	await _it_tires_sleeps_and_wakes_rested()
	await _running_out_of_energy_drops_it_once()
	await _a_thing_with_no_energy_never_sleeps()
	await _food_outranks_rest_and_a_trip_is_not_cut_short()
	await _sleeping_slows_hunger_without_stopping_it()
	await _a_grazer_eats_off_the_ground_with_no_inventory()
	await _a_sated_carrier_leaves_the_berry_alone()
	await _a_hungry_carrier_eats_off_the_ground_without_pocketing()
	await _one_berry_two_takers_one_tick()
	await _executors_need_a_flag_not_a_brain()
	await _every_state_raises_exactly_its_flag()
	await _a_stage_on_a_slower_tick_still_simulates_the_same()

## A component's `const NODE_KIND` is what gets it a node, so a berry — sprite,
## no shape — must come out with a sprite and no body. And everything an entity
## owns must hang under that entity's own container.
func _spawn_builds_declared_nodes() -> void:
	# A monkey: it carries, and the next test picks this same berry up out of
	# the world it leaves behind. A rabbit has no inventory at all since it
	# became a grazer.
	var rabbit := _manager.spawn(_world, _catalog, &"monkey", Vector2(50.0, 0.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(60.0, 0.0))
	await _tick(1)

	var box := _manager.container_for(rabbit)
	var view := _manager.node_for(rabbit, EcsConst.NODE_SPRITE)
	var body := _manager.node_for(rabbit, EcsConst.NODE_BODY)
	_check("a creature gets a container named for it",
		box != null and box.name == "entity_%d" % rabbit)
	_check("the container hangs under Entities", box != null and box.get_parent() == _entities)
	_check("a creature gets a sprite", view != null)
	_check("a creature gets a body", body != null)
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

## Picking up is a death with a record kept. The berry is captured — every
## component, and its uid — into the bag, flagged Dying on the spot, and gone
## with its nodes the tick after. What survives is data, and it is the same
## berry: the record's uid is the one the entity had.
func _pickup_keeps_a_record_and_ends_the_berry() -> void:
	var monkey := _first_of(&"monkey")
	var berry := _first_of(&"berry")
	var uid := (_world.get_component(berry, EcsNameComponent) as EcsNameComponent).uid
	var food := _world.get_component(berry, EcsConsumableComponent) as EcsConsumableComponent
	# An instance value the catalog does not know, to prove the snapshot is of
	# this berry and not of its blueprint.
	food.nutrition = 37.5
	# Taking is a decision, and this scheduler has no brain in it on purpose.
	# The test plays the brain by raising the flag the brain would.
	_intend_take(monkey, berry)
	# Two ticks: reach is what physics reported, and it reports after a step.
	await _tick(2)

	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent
	_check("every entity is born with a uid", uid.length() == 32)
	_check("the berry went into the bag as a record", _holds(bag, berry))
	_check("and is claimed for death on the spot", _world.has(berry, EcsDyingFlag))

	await _tick(1)
	var record: EcsItemRecord = bag.items[0] if not bag.items.is_empty() else null
	_check("next tick the entity is gone", not _world.is_alive(berry))
	_check("with its nodes", _manager.container_for(berry) == null)
	_check("the record kept its type", record != null and record.type_id == &"berry")
	_check("and its instance values, not the blueprint's", record != null
		and is_equal_approx((record.component(EcsConsumableComponent)
			as EcsConsumableComponent).nutrition, 37.5))
	_check("and its position, as it was when taken", record != null
		and record.component(EcsPositionComponent) != null)
	_check("but none of its flags", record != null and record.components.all(
		func(held: EcsComponent) -> bool: return not held is EcsFlag))

## Kill is the only thing that takes nodes away.
func _kill_takes_the_data_and_the_nodes() -> void:
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(600.0, -600.0))
	var containers_before := _entities.get_child_count()
	_world.add(berry, EcsDyingFlag.new())
	await _tick(1)

	_check("the killed entity is gone from the world", not _world.is_alive(berry))
	_check("its nodes are gone from the manager",
		_manager.node_for(berry, EcsConst.NODE_SPRITE) == null
		and _manager.container_for(berry) == null)
	_check("one container freed takes the whole entity with it",
		_entities.get_child_count() == containers_before - 1)

## A component is what an entity is and gets a tab of its own; a flag is what is
## true of it now, and all of them share one "Flags" tab, a line each. The
## inspector tells them apart by base class alone, naming no flag type.
func _flags_share_one_inspector_tab() -> void:
	var monkey := _first_of(&"monkey")
	var inspect := EcsInspectSystem.new()
	var before: Dictionary = inspect._snapshot(_world, monkey)["components"]
	_check("with no flags raised the Flags tab is there, and empty",
		before.has(&"flags") and (before[&"flags"]["fields"] as Dictionary).has("none"))

	_world.add(monkey, EcsSelectedFlag.new())
	_world.add(monkey, EcsCollapsedFlag.new())
	var sections: Dictionary = inspect._snapshot(_world, monkey)["components"]
	var flags: Dictionary = sections[&"flags"]["fields"]
	_check("both flags are listed on the one tab",
		flags.has("Selected") and flags.has("Collapsed") and not flags.has("none"))
	_check("and neither gets a tab of its own",
		not sections.has(&"selected") and not sections.has(&"collapsed"))
	_check("components still do", sections.has(&"hunger") and sections.has(&"inventory"))
	_check("the singletons are their own kind",
		_world.get_singleton(EcsLifecycleSingleton) is EcsSingleton)

	_world.remove(monkey, EcsSelectedFlag)
	_world.remove(monkey, EcsCollapsedFlag)

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
	# A monkey, because this one ends in a pickup and only a carrier picks up.
	var rabbit := _manager.spawn(_world, _catalog, &"monkey", Vector2(2000.0, 2000.0))
	var near := _manager.spawn(_world, _catalog, &"berry", Vector2(2000.0, 2100.0))
	var far := _manager.spawn(_world, _catalog, &"berry", Vector2(2000.0, 2900.0))
	var sensor := _world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent
	var action := _world.get_component(rabbit, EcsActionComponent) as EcsActionComponent
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	# Wanting it is a given here; what is under test is whether it can reach it.
	_intend_take(rabbit, near)
	await _tick(2)

	# 100 px away: inside the 280 px sensor, outside the 34 + 14 px reach.
	_check("it sees the berry 100 px away", sensor.perceived.has(near))
	_check("it does not see the one 900 px away", not sensor.perceived.has(far))
	_check("seeing is not reaching", not action.reached.has(near))
	_check("so it has not taken it", not _holds(bag, near))

	# Bring it to arm's length without moving the rabbit.
	(_world.get_component(near, EcsPositionComponent) as EcsPositionComponent).position \
		= Vector2(2000.0, 2030.0)
	await _tick(2)

	_check("once the bodies touch the action area, it is in reach",
		action.reached.has(near))
	_check("and it is taken", _holds(bag, near))
	_check("the one it never saw is untouched",
		_world.has(far, EcsPositionComponent) and not _holds(bag, far))

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
## This one runs its own scheduler, with the brain and movement added, because
## every other test above deliberately has no brain and no legs so that nothing
## moves except what the test moves.
##
## The brain now owns wandering too, so "it walked that way" could in principle
## be a coincidence. That is what the state check is for: it must be in
## SEEK_FOOD, aimed at *that* berry, before any of the distances mean anything.
func _it_walks_to_what_it_sees_and_takes_it() -> void:
	var walking := EcsScheduler.new()
	walking \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	# Far from everything else in this file, and outside the arena the wander
	# bounds clamp to, so no other entity drifts into the experiment.
	# A monkey, because this one is about carrying: a rabbit has no bag at all.
	var rabbit := _manager.spawn(_world, _catalog, &"monkey", Vector2(2000.0, -2000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(2200.0, -2000.0))
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	var at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var started := at.position
	# Since step 4 the food rung has a motive gate, and a rabbit spawns fed.
	# Empty enough to fetch, not empty enough to eat what it fetches — this
	# test is about walking and taking, and eating would end the berry early.
	var appetite := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	appetite.fullness = appetite.forage_below - 1.0

	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	# Not on the first tick. `sensor.perceived` is written from physics overlaps,
	# and a freshly spawned entity has none reported yet, so its opening move is
	# always a wander. The tick after, perception arrives and the food rung
	# preempts the wander mid-leg — which is the behaviour worth pinning down,
	# so this asserts it happens within a couple of ticks and not that it
	# happened instantly.
	for i in 3:
		walking.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.SEEK_FOOD:
			break
	_check("it chose to seek food, not to wander",
		brain.state == EcsLowBrainComponent.State.SEEK_FOOD)
	_check("and committed to the berry it saw", brain.target == berry)

	# 200 px at the monkey's 130 px/sec is about 1.5 seconds. 240 ticks is four,
	# and the loop breaks the moment the berry is in the bag anyway.
	for i in 240:
		walking.run_all(_world, TICK)
		await get_tree().physics_frame
		if _holds(bag, berry):
			break

	_check("it walked toward the berry it could see", at.position.x > started.x + 100.0)
	_check("and picked it up on arrival", _holds(bag, berry))
	_check("which is what leaving the world means",
		not _world.is_alive(berry) or _world.has(berry, EcsDyingFlag))
	_check("it stopped at arm's length, not on top of it",
		at.position.distance_to(Vector2(2200.0, -2000.0)) > 20.0)

	# The brain runs before pickup, so on the tick the berry was taken it still
	# believed it was seeking. It finds out on the next one — the ordinary
	# one-tick lag of a pipeline where each stage reads what the last one left.
	walking.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("and let the commitment go once the berry was gone",
		brain.target == EcsWorld.NO_ENTITY
		and brain.state != EcsLowBrainComponent.State.SEEK_FOOD)

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

	# Tightened from the blueprint's defaults so the test runs in a couple of
	# seconds rather than eight. The expected budget is then derived from the
	# component rather than written down, so retuning a creature's speed cannot
	# quietly turn this into a test of nothing.
	move.timeout_slack = 1.0
	move.timeout_grace = 0.5
	move.destination = bush_at
	move.has_destination = true
	var trip := bush_at.distance_to(started)
	var budget := trip / move.speed * move.timeout_slack + move.timeout_grace
	var expected := budget / TICK

	var ticks := 0
	for i in roundi(expected * 2.0) + 60:
		blocked.run_all(_world, TICK)
		await get_tree().physics_frame
		ticks += 1
		if not move.has_destination:
			break

	_check("it walked at the bush it could not stand in", at.position.x > started.x + 20.0)
	_check("and was still held short of it", at.position.distance_to(bush_at) > move.arrive_radius)
	_check("the trip timed out instead of pushing forever", not move.has_destination)
	_check("it ran roughly the budget it was priced (%d ticks, expected ~%d)"
		% [ticks, roundi(expected)],
		ticks > expected * 0.75 and ticks < expected * 1.25)
	_check("and the clock is back to zero for the next trip",
		is_zero_approx(move.time_left))

## What the state machine bought. A forager commits to a berry, and the berry
## is taken by somebody else mid-walk. The old stateless rung could only fill an
## *empty* destination slot, never take a full one, so it kept walking to the
## empty grass and only re-decided on arrival. With `target` on the component
## the brain can tell its commitment died, and calls the trip off on the tick it
## notices.
func _a_stolen_target_is_dropped_the_tick_it_vanishes() -> void:
	var thinking := EcsScheduler.new()
	thinking \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-2000.0, 2000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-1800.0, 2000.0))
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var move := _world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent
	# Empty enough to want it; no EcsHungerSystem here, so it stays put.
	var appetite := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	appetite.fullness = appetite.forage_below - 1.0

	for i in 30:
		thinking.run_all(_world, TICK)
		await get_tree().physics_frame

	_check("it is committed to the berry", brain.target == berry
		and brain.state == EcsLowBrainComponent.State.SEEK_FOOD)
	var committed_to := move.destination
	_check("and walking to it", move.has_destination)

	# Somebody else takes it: losing its position is what leaving the world
	# means, and it is exactly what EcsPickupSystem does.
	_world.remove(berry, EcsPositionComponent)
	thinking.run_all(_world, TICK)
	await get_tree().physics_frame

	_check("the commitment was dropped the moment the berry left",
		brain.target == EcsWorld.NO_ENTITY)
	_check("and it is no longer seeking food",
		brain.state != EcsLowBrainComponent.State.SEEK_FOOD)
	_check("the walk to the empty grass was called off",
		not move.has_destination or not move.destination.is_equal_approx(committed_to))
	_check("with the trip clock reset, so the next one is priced fresh",
		is_zero_approx(move.time_left) or move.has_destination)


## Hunger is the *motive*: below its forage threshold a creature must wander
## past food it can plainly see, and above it must go and get it. Before step 4
## the food rung fired whenever the bag had room, which is gathering with no
## reason behind it.
func _hunger_climbs_and_gates_the_food_rung() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsHungerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-4000.0, 0.0))
	_manager.spawn(_world, _catalog, &"berry", Vector2(-3900.0, 0.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent

	# Sated, with a berry 100 px away and well inside its 280 px sensor.
	hunger.fullness = hunger.max_fullness
	var sated_state := EcsLowBrainComponent.State.SEEK_FOOD
	for i in 20:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		sated_state = brain.state
		if sated_state == EcsLowBrainComponent.State.SEEK_FOOD:
			break
	_check("a sated creature ignores food it can see",
		sated_state != EcsLowBrainComponent.State.SEEK_FOOD)
	_check("and fullness drained while it did", hunger.fullness < hunger.max_fullness)

	# Now make it hungry enough to bother.
	hunger.fullness = hunger.forage_below - 1.0
	for i in 20:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.SEEK_FOOD:
			break
	_check("a hungry one goes after the same berry",
		brain.state == EcsLowBrainComponent.State.SEEK_FOOD)

## Eating is a kill, where picking up is not: the berry leaves the bag AND the
## world, nodes and all, through the one owner of entity lifetime.
func _eating_empties_the_bag_and_ends_the_berry() -> void:
	var living := EcsScheduler.new()
	# No EcsHungerSystem on purpose: it would add a tick's worth of hunger in
	# the same frame the meal takes some off, and this checks the meal exactly.
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"monkey", Vector2(-4000.0, 1000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-4000.0, 1100.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	var food := _world.get_component(berry, EcsConsumableComponent) as EcsConsumableComponent
	await _tick(1)

	# Hand it the berry the way EcsPickupSystem would, and make it hungry.
	bag.items.append(EcsItemRecord.capture(_world, berry))
	_world.add(berry, EcsDyingFlag.new())
	hunger.fullness = hunger.eat_below - 5.0
	var before := hunger.fullness

	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("it decided to eat what it was carrying",
		brain.state == EcsLowBrainComponent.State.EAT)
	_check("the berry left the bag", not _holds(bag, berry))
	_check("and fullness rose by the berry's nutrition",
		is_equal_approx(hunger.fullness, before + food.nutrition))
	_check("the intent named the record, not an entity",
		brain.target == EcsWorld.NO_ENTITY)

## The consequence that makes hunger more than a number: pinned at the top it
## costs health, and health at zero is the module's first death by simulation.
func _starving_costs_health_and_then_the_entity() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHungerSystem.new()) \
		.add(EcsHealthSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-4000.0, 2000.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var health := _world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent
	await _tick(1)

	# Not starving yet: one tick short of the top costs nothing.
	hunger.fullness = 1.0
	health.value = health.max_health
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("being merely peckish is free", is_equal_approx(health.value, health.max_health))

	hunger.fullness = 0.0
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("starving costs health", health.value < health.max_health)

	health.value = 0.0
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("health at zero is still alive for the rest of that tick",
		_world.is_alive(rabbit))
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("and dead at the next lifecycle stage", not _world.is_alive(rabbit))
	_check("with its container freed", _manager.container_for(rabbit) == null)

## Eating must not depend on owning a pocket. A rabbit has no
## EcsInventoryComponent at all: it walks to the berry and eats it where it
## lies, off the ground, through the action area it already had for reaching.
##
## The whole chain end to end, with nothing handed to it by the test: hunger
## climbs, the food rung fires, it walks, the eat rung fires on arrival, and
## the berry is killed rather than pocketed.
func _a_grazer_eats_off_the_ground_with_no_inventory() -> void:
	var grazing := EcsScheduler.new()
	grazing \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHungerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-6000.0, 0.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-5850.0, 0.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent

	_check("a rabbit carries nothing at all",
		not _world.has(rabbit, EcsInventoryComponent))

	# Empty enough to fetch. Its eat_below sits *above* forage_below precisely
	# because it cannot stockpile — it eats what it walks to, on arrival.
	hunger.fullness = hunger.forage_below - 1.0
	_check("and its thresholds say graze, not hoard", hunger.eat_below > hunger.forage_below)
	var before := hunger.fullness

	var ate := false
	for i in 400:
		grazing.run_all(_world, TICK)
		await get_tree().physics_frame
		if not _world.is_alive(berry):
			ate = true
			break

	_check("it walked to the berry and ate it off the ground", ate)
	_check("without ever holding it", not _world.has(rabbit, EcsInventoryComponent))
	_check("fullness went up, not down", hunger.fullness > before)
	_check("and its nodes went with it", _manager.container_for(berry) == null)
	_check("it is no longer eating", brain.state != EcsLowBrainComponent.State.EAT)

func _tick(count: int) -> void:
	for i in count:
		_scheduler.run_all(_world, TICK)
		await get_tree().physics_frame

## What making pickup a decision is for. A full monkey standing on a berry used
## to pocket it anyway, because EcsPickupSystem ran on reach alone and nothing
## had chosen anything. Now the brain gates it on the same hunger that would
## send it out for food in the first place.
func _a_sated_carrier_leaves_the_berry_alone() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var monkey := _manager.spawn(_world, _catalog, &"monkey", Vector2(-6000.0, 3000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-6000.0, 3020.0))
	var hunger := _world.get_component(monkey, EcsHungerComponent) as EcsHungerComponent
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent
	var action := _world.get_component(monkey, EcsActionComponent) as EcsActionComponent

	# Right on top of it, and no EcsHungerSystem here so the bar stays put.
	hunger.fullness = hunger.max_fullness
	for i in 20:
		living.run_all(_world, TICK)
		await get_tree().physics_frame

	_check("the berry is well within its reach", action.reached.has(berry))
	_check("but a sated carrier does not pocket it", not _holds(bag, berry))

	# Empty enough to want it, and it takes it without moving an inch.
	hunger.fullness = hunger.forage_below - 1.0
	for i in 20:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if _holds(bag, berry):
			break

	_check("once hungry, the same berry goes in the bag", _holds(bag, berry))
	_check("which is a decision, not a reflex — it had to want it first",
		not _world.is_alive(berry) or _world.has(berry, EcsDyingFlag))

## The rung order, pinned. A carrier hungry enough to eat, standing over a
## berry, must eat it where it lies — not pocket it and then take it back out.
##
## The end state cannot tell you which happened: with a one-slot bag, TAKE then
## EAT leaves exactly the same dead berry and the same fed monkey as EAT alone.
## So this watches the *path* and fails if the bag is ever non-empty. Reorder
## EAT below TAKE and only this check notices.
##
## Carrying is provisioning, not a step on the way to a meal: you fill the bag
## while wandering so that later hunger is answered on the spot.
func _a_hungry_carrier_eats_off_the_ground_without_pocketing() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var monkey := _manager.spawn(_world, _catalog, &"monkey", Vector2(-6000.0, 5000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-6000.0, 5020.0))
	var hunger := _world.get_component(monkey, EcsHungerComponent) as EcsHungerComponent
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent

	_check("the carrier has a bag it could have used", bag != null)
	# Empty enough to eat, which is past the threshold that would pocket it.
	# No EcsHungerSystem here, so the bar stays where the test puts it.
	hunger.fullness = hunger.eat_below - 5.0
	var before := hunger.fullness

	var pocketed := false
	var ate := false
	for i in 120:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if not bag.items.is_empty():
			pocketed = true
		if not _world.is_alive(berry):
			ate = true
			break

	_check("it ate the berry off the ground", ate)
	_check("and never put it in the bag on the way", not pocketed)
	_check("the meal went onto its fullness", hunger.fullness > before)

## Two executors, one berry, one tick: a grazer eating it off the ground and a
## carrier taking it into its bag. Consume runs first, so the grazer wins — and
## the carrier must then find it claimed. Death is deferred to the next tick, so
## for the rest of this one the berry still exists; what stops the second taker
## is that the claim is instant, not that the berry is gone. Neither creature
## learns the other meant to have it: the executors, running one at a time, are
## the single authority that settles it.
func _one_berry_two_takers_one_tick() -> void:
	var contest := EcsScheduler.new()
	contest \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsPickupSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-9000.0, 0.0))
	var monkey := _manager.spawn(_world, _catalog, &"monkey", Vector2(-9000.0, 40.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-9000.0, 20.0))
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent

	# Let physics report who touches what, with neither creature meaning anything.
	for i in 3:
		contest.run_all(_world, TICK)
		await get_tree().physics_frame
	var rabbit_reach := _world.get_component(rabbit, EcsActionComponent) as EcsActionComponent
	var monkey_reach := _world.get_component(monkey, EcsActionComponent) as EcsActionComponent
	_check("both creatures have the berry in reach",
		rabbit_reach.reached.has(berry) and monkey_reach.reached.has(berry))

	_intend_eat(rabbit, berry)
	_intend_take(monkey, berry)
	contest.run_all(_world, TICK)
	await get_tree().physics_frame

	_check("the grazer ate it: it is claimed for death", _world.has(berry, EcsDyingFlag))
	_check("so the carrier did not also take it", not _holds(bag, berry))

	_world.remove(rabbit, EcsEatIntentFlag)
	_world.remove(monkey, EcsTakeIntentFlag)
	contest.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("and next tick it is gone", not _world.is_alive(berry))
	for id in [rabbit, monkey]:
		_world.add(id, EcsDyingFlag.new())
	contest.run_all(_world, TICK)

## Step 6's point, tested directly: the executors and the rate systems act on a
## flag, so an entity with **no brain at all** eats, takes and sleeps when one is
## raised on it. Nothing here ever reads EcsLowBrainComponent — the brain is
## removed first so that nothing could.
func _executors_need_a_flag_not_a_brain() -> void:
	var acting := EcsScheduler.new()
	acting \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsEnergySystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsPickupSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-15000.0, 0.0))
	var monkey := _manager.spawn(_world, _catalog, &"monkey", Vector2(-15000.0, 3000.0))
	var meal := _manager.spawn(_world, _catalog, &"berry", Vector2(-15000.0, 20.0))
	var prize := _manager.spawn(_world, _catalog, &"berry", Vector2(-15000.0, 3020.0))
	# Deliberately breaking the component guideline, for a test: nothing may be
	# able to consult a brain, so there is none to consult.
	_world.remove(rabbit, EcsLowBrainComponent)
	_world.remove(monkey, EcsLowBrainComponent)
	for i in 3:
		acting.run_all(_world, TICK)
		await get_tree().physics_frame

	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.eat_below - 5.0
	var before := hunger.fullness
	_intend_eat(rabbit, meal)
	_intend_take(monkey, prize)
	acting.run_all(_world, TICK)
	await get_tree().physics_frame

	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent
	_check("a brainless grazer with an eat flag eats", _world.has(meal, EcsDyingFlag)
		and hunger.fullness > before)
	_check("a brainless carrier with a take flag takes", _holds(bag, prize))

	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.value = energy.max_energy * 0.5
	_world.add(rabbit, EcsAsleepFlag.new())
	for i in 30:
		acting.run_all(_world, TICK)
	_check("a brainless sleeper with the asleep flag gets energy back",
		energy.value > energy.max_energy * 0.5)

	for id in [rabbit, monkey, prize]:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	acting.run_all(_world, TICK)

## `state` is the brain's memory and the flags are its instructions, written in
## one place so they cannot drift. Run the whole deciding pipeline over a
## hungry grazer and a hungry carrier among berries, and check on every tick
## that each creature's flags are exactly the ones its state implies — and that
## the eat and take states were actually visited, or the check proved nothing.
func _every_state_raises_exactly_its_flag() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var creatures: Array[int] = [
		_manager.spawn(_world, _catalog, &"rabbit", Vector2(-18000.0, 0.0)),
		_manager.spawn(_world, _catalog, &"monkey", Vector2(-18000.0, 200.0)),
	]
	var berries: Array[int] = []
	for i in 6:
		berries.append(_manager.spawn(_world, _catalog, &"berry",
			Vector2(-18100.0 + i * 40.0, 100.0)))
	var rabbit_hunger := _world.get_component(creatures[0], EcsHungerComponent) as EcsHungerComponent
	rabbit_hunger.fullness = rabbit_hunger.forage_below - 1.0
	var monkey_hunger := _world.get_component(creatures[1], EcsHungerComponent) as EcsHungerComponent
	monkey_hunger.fullness = monkey_hunger.forage_below - 1.0

	var disagreements := 0
	var seen := {}
	for tick in 400:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		for id in creatures:
			var brain := _world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
			seen[brain.state] = true
			var eat := _world.has(id, EcsEatIntentFlag)
			var take := _world.has(id, EcsTakeIntentFlag)
			var asleep := _world.has(id, EcsAsleepFlag)
			var want_eat := brain.state == EcsLowBrainComponent.State.EAT
			var want_take := brain.state == EcsLowBrainComponent.State.TAKE
			var want_asleep := brain.state == EcsLowBrainComponent.State.SLEEP
			if eat != want_eat or take != want_take or asleep != want_asleep:
				disagreements += 1

	_check("flags and state agreed on every tick (%d disagreements)" % disagreements,
		disagreements == 0)
	_check("and the run did visit EAT and TAKE",
		seen.has(EcsLowBrainComponent.State.EAT) and seen.has(EcsLowBrainComponent.State.TAKE))

	for id in creatures + berries:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)

## Running a stage a third as often must not make it simulate a third as much.
## The scheduler banks delta per system, so hunger authored in points per second
## climbs at that rate whether it is ticked at 60 Hz or 20 Hz — nothing is
## scaled by hand, which is the whole reason a per-stage rate is safe here.
##
## Also checks `phase`, which is what keeps two slow stages off the same frame:
## a stage at phase 1 must sit out tick 0 and run on tick 1.
func _a_stage_on_a_slower_tick_still_simulates_the_same() -> void:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-8000.0, 0.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	await _tick(1)

	# 60 Hz.
	var fast := EcsScheduler.new()
	fast.add(EcsHungerSystem.new())
	hunger.fullness = hunger.max_fullness
	for i in 30:
		fast.run_all(_world, TICK)
	var at_60 := hunger.max_fullness - hunger.fullness

	# 20 Hz, same wall-clock span.
	var slow := EcsScheduler.new()
	slow.add(EcsHungerSystem.new(), 3, 0)
	hunger.fullness = hunger.max_fullness
	for i in 30:
		slow.run_all(_world, TICK)
	var at_20 := hunger.max_fullness - hunger.fullness

	_check("fullness drained at 60 Hz", at_60 > 0.0)
	# At most one interval's worth may still be banked when the span ends.
	var owed := hunger.drain * 3.0 * TICK
	_check("and by the same amount at 20 Hz (%.4f vs %.4f, one interval = %.4f)"
		% [at_60, at_20, owed], absf(at_60 - at_20) <= owed + 0.0001)

	# Phase: this one must sit out the first tick and act on the second.
	var offset := EcsScheduler.new()
	offset.add(EcsHungerSystem.new(), 3, 1)
	hunger.fullness = hunger.max_fullness
	offset.run_all(_world, TICK)
	_check("a stage at phase 1 sits out tick 0",
		is_equal_approx(hunger.fullness, hunger.max_fullness))
	offset.run_all(_world, TICK)
	_check("and runs on tick 1, with both ticks of delta banked",
		is_equal_approx(hunger.max_fullness - hunger.fullness, hunger.drain * 2.0 * TICK))

## The other half of hunger's rule. Starving spends health; being well fed gives
## it back, and the band between the two thresholds does neither — which is what
## stops regeneration from simply undoing starvation.
func _being_well_fed_mends_and_the_band_between_does_neither() -> void:
	var living := EcsScheduler.new()
	living.add(EcsHungerSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-8000.0, 2000.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var health := _world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent
	await _tick(1)

	# Well fed and wounded: it mends.
	hunger.fullness = hunger.max_fullness
	health.value = 50.0
	for i in 30:
		living.run_all(_world, TICK)
	_check("a well-fed creature mends", health.value > 50.0)

	# Between the thresholds: neither mending nor starving.
	hunger.fullness = (hunger.heal_above + hunger.eat_below) * 0.5
	var held := health.value
	for i in 30:
		living.run_all(_world, TICK)
	_check("and the band between does neither", is_equal_approx(health.value, held))

	# Mending stops at full, rather than running past it.
	hunger.fullness = hunger.max_fullness
	health.value = health.max_health - 0.1
	for i in 60:
		living.run_all(_world, TICK)
	_check("mending stops at full health",
		is_equal_approx(health.value, health.max_health))

	# And empty still costs, so the two halves are the same rule.
	hunger.fullness = 0.0
	for i in 30:
		living.run_all(_world, TICK)
	_check("while empty still costs health", health.value < health.max_health)

## The ordinary cycle: awake costs, moving costs more, low energy puts it down,
## and sleeping brings it back up to `wake_at` and no further.
func _it_tires_sleeps_and_wakes_rested() -> void:
	var living := EcsScheduler.new()
	living.add(EcsEnergySystem.new()).add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-9000.0, 0.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var move := _world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.max_fullness
	await _tick(1)

	# Standing still costs drain_idle.
	energy.value = energy.max_energy
	move.velocity = Vector2.ZERO
	for i in 60:
		living.run_all(_world, TICK)
	var idle_cost := energy.max_energy - energy.value
	_check("being awake costs energy", idle_cost > 0.0)

	# Walking costs more. Velocity is what movement leaves behind, so the test
	# sets it the way movement would.
	energy.value = energy.max_energy
	for i in 60:
		move.velocity = Vector2(80.0, 0.0)
		living.run_all(_world, TICK)
	_check("and moving costs more than standing",
		energy.max_energy - energy.value > idle_cost)

	# Tired, with nothing to eat and nothing in sight: it lies down.
	move.velocity = Vector2.ZERO
	energy.value = energy.rest_at - 1.0
	living.run_all(_world, TICK)
	_check("a tired creature sleeps", brain.state == EcsLowBrainComponent.State.SLEEP)
	_check("and drops whatever trip it had", not move.has_destination)

	# Still below wake_at: it stays down rather than flickering.
	energy.value = (energy.rest_at + energy.wake_at) * 0.5
	living.run_all(_world, TICK)
	_check("and stays down between rest_at and wake_at",
		brain.state == EcsLowBrainComponent.State.SLEEP)

	# Sleeping puts it back, at `restore` per second.
	energy.value = energy.rest_at * 0.5
	var slept_from := energy.value
	for i in 30:
		living.run_all(_world, TICK)
	_check("sleeping restores energy", energy.value > slept_from)

	# Rested: it gets up on its own.
	energy.value = energy.wake_at
	living.run_all(_world, TICK)
	_check("then wakes once rested", brain.state != EcsLowBrainComponent.State.SLEEP)

	# Starving interrupts a voluntary sleep — the first thing in this module
	# that preempts a standing state rather than filling an empty slot.
	energy.value = energy.rest_at - 1.0
	living.run_all(_world, TICK)
	_check("it sleeps again when tired", brain.state == EcsLowBrainComponent.State.SLEEP)
	hunger.fullness = 0.0
	living.run_all(_world, TICK)
	_check("but starving wakes it", brain.state != EcsLowBrainComponent.State.SLEEP)

## Running out entirely is not a decision. The tag is the lock, the damage is
## paid once at the moment of crossing, and coming round leaves an ordinary
## sleeper rather than a free creature.
func _running_out_of_energy_drops_it_once() -> void:
	var living := EcsScheduler.new()
	living.add(EcsEnergySystem.new()).add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-9000.0, 2000.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	var health := _world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.max_fullness
	await _tick(1)

	energy.value = 0.0
	health.value = health.max_health
	living.run_all(_world, TICK)
	_check("empty energy collapses it", _world.has(rabbit, EcsCollapsedFlag))
	_check("the collapse cost exactly collapse_damage once",
		is_equal_approx(health.value, health.max_health - energy.collapse_damage))
	_check("and it is down", brain.state == EcsLowBrainComponent.State.SLEEP)

	# Many more ticks must not charge for it again.
	for i in 30:
		living.run_all(_world, TICK)
	_check("and is not charged for it again",
		is_equal_approx(health.value, health.max_health - energy.collapse_damage))

	# The lock holds even against starving, which would wake a chosen sleep.
	hunger.fullness = 0.0
	living.run_all(_world, TICK)
	_check("starving cannot wake a collapsed creature",
		brain.state == EcsLowBrainComponent.State.SLEEP)

	# Come round, still tired, and now an ordinary sleeper again.
	energy.value = energy.collapse_release
	living.run_all(_world, TICK)
	_check("the lock lifts at collapse_release",
		not _world.has(rabbit, EcsCollapsedFlag))
	living.run_all(_world, TICK)
	_check("and starving can wake it now",
		brain.state != EcsLowBrainComponent.State.SLEEP)

	# Something with energy but no health collapses without complaint — the
	# same way something with no health starves forever.
	_world.remove(rabbit, EcsHealthComponent)
	_world.remove(rabbit, EcsCollapsedFlag)
	energy.value = 0.0
	living.run_all(_world, TICK)
	_check("an entity with no health collapses without error",
		_world.has(rabbit, EcsCollapsedFlag))

## Nothing without an EcsEnergyComponent ever tires or sleeps, and no flag says
## so — a berry is the proof.
func _a_thing_with_no_energy_never_sleeps() -> void:
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-9000.0, 4000.0))
	await _tick(1)
	_check("a berry carries no energy", not _world.has(berry, EcsEnergyComponent))
	_check("and never collapses", not _world.has(berry, EcsCollapsedFlag))

## The plan's rule that nothing else pins down: **food outranks rest.** A tired
## creature that can see a berry goes for it, and the trip it commits to is not
## cut short by getting tireder on the way. The consequence — that a creature
## which keeps finding food can run itself into a collapse — is the price of
## that ordering, not a bug.
func _food_outranks_rest_and_a_trip_is_not_cut_short() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsEnergySystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-11000.0, 0.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-10850.0, 0.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	await _tick(2)

	# Tired enough to sleep, and empty enough to forage, with food in sight.
	energy.value = energy.rest_at - 1.0
	hunger.fullness = hunger.forage_below - 5.0
	for i in 4:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("a tired creature that can see food goes for it",
		brain.state == EcsLowBrainComponent.State.SEEK_FOOD)
	_check("and committed to that berry", brain.target == berry)

	# Getting tireder mid-trip must not call it off.
	energy.value = 1.0
	for i in 4:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("and the trip is not cut short by tiredness",
		brain.state == EcsLowBrainComponent.State.SEEK_FOOD)

	# But running out entirely is not a decision, so it does override the trip.
	energy.value = 0.0
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("though a collapse does override it",
		_world.has(rabbit, EcsCollapsedFlag)
		and brain.state == EcsLowBrainComponent.State.SLEEP)

## A sleeper still gets hungry, just slower. Both halves matter: slower is the
## point, and *still* is what keeps the wake-on-starving rule reachable — a
## sleeper that never emptied would have no reason to get up before it was
## rested, and `asleep_drain_scale` at 0 would quietly remove that rule.
func _sleeping_slows_hunger_without_stopping_it() -> void:
	var living := EcsScheduler.new()
	living.add(EcsHungerSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-12000.0, 0.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	await _tick(1)

	hunger.fullness = hunger.max_fullness
	for i in 60:
		living.run_all(_world, TICK)
	var awake_cost := hunger.max_fullness - hunger.fullness

	# The flag alone, no brain state: hunger reads the fact, not the brain.
	_world.add(rabbit, EcsAsleepFlag.new())
	hunger.fullness = hunger.max_fullness
	for i in 60:
		living.run_all(_world, TICK)
	var asleep_cost := hunger.max_fullness - hunger.fullness

	_check("a sleeper still gets hungry", asleep_cost > 0.0)
	_check("but slower than awake (%.3f vs %.3f)" % [asleep_cost, awake_cost],
		asleep_cost < awake_cost)
	_check("by the authored fraction",
		is_equal_approx(asleep_cost, awake_cost * hunger.asleep_drain_scale))

	# A collapse is a forced sleep, and costs the same reduced rate.
	_world.remove(rabbit, EcsAsleepFlag)
	_world.add(rabbit, EcsCollapsedFlag.new())
	hunger.fullness = hunger.max_fullness
	for i in 60:
		living.run_all(_world, TICK)
	_check("and a collapse counts as asleep too",
		is_equal_approx(hunger.max_fullness - hunger.fullness, asleep_cost))
	_world.remove(rabbit, EcsCollapsedFlag)

## Raise an intent flag directly, for the tests that run an executor without
## EcsLowBrainSystem to decide for them. The test plays the brain — and since
## the executors read only the flag, that is all playing the brain takes.
func _intend_take(id: int, target: int) -> void:
	var take := EcsTakeIntentFlag.new()
	take.target_id = target
	_world.add(id, take)

func _intend_eat(id: int, target: int) -> void:
	var eat := EcsEatIntentFlag.new()
	eat.target_id = target
	_world.add(id, eat)

## Does `bag` hold a record of entity `id`? Matched by uid, since a carried item
## is no longer an entity. The uid is remembered the first time it is asked
## while the entity is alive, so the question still has an answer after it dies.
func _holds(bag: EcsInventoryComponent, id: int) -> bool:
	if _world.is_alive(id):
		_uids[id] = (_world.get_component(id, EcsNameComponent) as EcsNameComponent).uid
	var uid: String = _uids.get(id, "")
	return uid != "" and bag.items.any(func(record: EcsItemRecord) -> bool:
		return record.uid == uid)

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
