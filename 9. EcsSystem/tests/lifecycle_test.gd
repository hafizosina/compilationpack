extends Node2D

## Headless acceptance test for module 9: lifecycle, sensors, collision, the
## brain, needs, intent flags, item records and views.
##
##   "$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn"
##
## Exits 0 only if every check passes. Each tick awaits a physics frame so
## overlaps are reported.

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
	_world.add_singleton(EcsCombatSingleton.new())

	# No brain or movement here, so nothing moves unless the test moves it.
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
	await _a_dead_carrier_puts_back_what_it_carried()
	await _animals_of_one_kind_start_differently_rested()
	await _a_stage_on_a_slower_tick_still_simulates_the_same()
	_a_view_is_kept_until_a_table_it_names_changes()
	await _a_hit_lands_less_armour_on_cooldown_and_can_crit()
	await _death_by_health_leaves_a_corpse_to_loot_and_eat()
	await _a_corpse_rots_and_spills_what_it_held()
	await _a_hungry_hunter_kills_its_prey_and_eats_the_corpse()

## Nodes match the declared NODE_KINDs (a berry gets a sprite and a body, no
## sensor) and hang under the entity's own container.
func _spawn_builds_declared_nodes() -> void:
	# A monkey, since the next test picks this berry up and only carriers can.
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
	# Layers come from the components' NODE_LAYER / NODE_MASK.
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

## Picking up stores a record (same uid) in the bag and kills the entity and its
## nodes the next tick.
func _pickup_keeps_a_record_and_ends_the_berry() -> void:
	var monkey := _first_of(&"monkey")
	var berry := _first_of(&"berry")
	var uid := (_world.get_component(berry, EcsNameComponent) as EcsNameComponent).uid
	var food := _world.get_component(berry, EcsConsumableComponent) as EcsConsumableComponent
	# An instance value, to show the record copies this berry, not its blueprint.
	food.nutrition = 37.5
	# No brain here, so the test raises the intent flag itself.
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

## Components get their own inspector tab; flags share one "Flags" tab.
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
	_check("components still do", sections.has(&"inventory") and sections.has(&"movement"))
	var snapshot: Dictionary = inspect._snapshot(_world, monkey)
	var named := _world.get_component(monkey, EcsNameComponent) as EcsNameComponent
	_check("the name component has no tab of its own", not sections.has(&"name"))
	_check("its entity name is on the Entity tab instead",
		snapshot["fields"].get("entity_name") == String(named.entity_name))
	_check("and so is its position, with no Position tab",
		not sections.has(&"position") and snapshot["fields"].has("position"))
	var bars := _world.get_component(monkey, EcsHealthComponent) as EcsHealthComponent
	_check("the three bars are on the Entity tab, each under its own label",
		snapshot["fields"].has("fullness") and snapshot["fields"].has("energy")
		and snapshot["fields"].get("health") == "%d/%d" % [roundi(bars.value), roundi(bars.max_health)])
	_check("with no tabs of their own",
		not sections.has(&"hunger") and not sections.has(&"energy") and not sections.has(&"health"))
	_check("body, sprite, brain, sensor and action are not shown at all",
		not sections.has(&"body") and not sections.has(&"sprite")
		and not sections.has(&"low_brain") and not sections.has(&"sensor")
		and not sections.has(&"action"))
	_check("but every component is still named on the components line",
		String(snapshot["fields"].get("components")).contains("body")
		and String(snapshot["fields"].get("components")).contains("name"))
	var source := (load("res://9. EcsSystem/systems/ecs_inspect_system.gd") as GDScript).source_code
	var names_one := RegEx.create_from_string("Ecs[A-Za-z]+Component\\b").search(source)
	_check("the inspector names no component type — each describes itself",
		names_one == null)
	_check("the singletons are their own kind",
		_world.get_singleton(EcsLifecycleSingleton) is EcsSingleton)

	_world.remove(monkey, EcsSelectedFlag)
	_world.remove(monkey, EcsCollapsedFlag)

## A spawner's request is fulfilled next tick and it records the new id.
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

## Soft collision separates overlapping bodies.
func _collision_still_separates_manager_owned_bodies() -> void:
	var a := _manager.spawn(_world, _catalog, &"rabbit", Vector2(1000.0, 0.0))
	var b := _manager.spawn(_world, _catalog, &"rabbit", Vector2(1002.0, 0.0))
	# Areas follow their containers; if not, both would sit at the origin.
	var pa := _world.get_component(a, EcsPositionComponent) as EcsPositionComponent
	var pb := _world.get_component(b, EcsPositionComponent) as EcsPositionComponent
	var started := pa.position.distance_to(pb.position)

	await _tick(40)

	var ended := pa.position.distance_to(pb.position)
	var touching := _radius_of(a) + _radius_of(b)
	_check("two stacked bodies pushed apart (%.1f -> %.1f px, touching at %.1f)"
		% [started, ended, touching], ended > started)
	_check("and settled at least their combined radii apart", ended >= touching - 0.5)

## A forager perceives a berry inside its sensor and reaches it only once its
## action area touches the berry's body.
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

## A walker is pushed out of a solid immovable bush, and the bush doesn't move.
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

## A non-solid berry is walked over: nothing moves. No pickup in this scheduler,
## so the overlap stays.
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
	# 10 px apart with bodies of 22 and 14: deeply overlapping.
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

## End to end: a forager sees a berry out of reach, commits to it (SEEK_FOOD),
## walks to it and takes it.
func _it_walks_to_what_it_sees_and_takes_it() -> void:
	var walking := EcsScheduler.new()
	walking \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	# Far from the rest of the test and outside the wander bounds.
	# A monkey, because this test is about carrying.
	var rabbit := _manager.spawn(_world, _catalog, &"monkey", Vector2(2000.0, -2000.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(2200.0, -2000.0))
	var bag := _world.get_component(rabbit, EcsInventoryComponent) as EcsInventoryComponent
	var at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var started := at.position
	# Hungry enough to fetch, not hungry enough to eat it.
	var appetite := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	appetite.fullness = appetite.forage_below - 1.0

	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	# Perception arrives a tick after spawn, so allow a couple of ticks.
	for i in 3:
		walking.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.SEEK_FOOD:
			break
	_check("it chose to seek food, not to wander",
		brain.state == EcsLowBrainComponent.State.SEEK_FOOD)
	_check("and committed to the berry it saw", brain.target == berry)

	# About 1.5 s of walking; 240 ticks is plenty.
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

	# The brain notices the pickup one tick later.
	walking.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("and let the commitment go once the berry was gone",
		brain.target == EcsWorld.NO_ENTITY
		and brain.state != EcsLowBrainComponent.State.SEEK_FOOD)

## A destination it can never reach (the centre of a solid bush) times out
## instead of leaving the walker stuck.
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

	# Tighter than the defaults so the test is quick; the expected budget is
	# computed from the component.
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

## When a committed target is taken by someone else, the brain drops the trip on
## the tick it notices.
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

	# Someone else takes it.
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


## Above `forage_below` it ignores food in sight; below it, it goes for it.
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

## Eating from the bag removes the record, and eating from the ground kills the
## entity and its nodes.
func _eating_empties_the_bag_and_ends_the_berry() -> void:
	var living := EcsScheduler.new()
	# No EcsHungerSystem, so the meal's effect can be checked exactly.
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

## Starving costs health, and zero health kills.
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

## A grazer (no inventory) walks to a berry and eats it off the ground, end to end.
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

	# Hungry enough to fetch; a grazer eats on arrival.
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

## A fed monkey standing on a berry doesn't pick it up; a hungry one does.
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

## A carrier hungry enough to eat, standing on a berry, eats it from the ground
## and never bags it first (EAT outranks TAKE). Checks the bag stays empty.
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
	# Hungry enough to eat. No EcsHungerSystem, so the bar stays put.
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

## A grazer and a carrier going for the same berry in one tick: consume runs
## first, so the grazer gets it and pickup sees it claimed.
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

## With no brain at all, raising intent flags still makes an entity eat, take
## and sleep.
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
	# Remove the brain so nothing can read it.
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
	energy.rolled = true  # the test sets energy by hand; no start roll
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

## Over a live run, every creature's flags match its state on every tick, and
## EAT and TAKE are both visited.
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

## When a carrier dies, its records return to the world where it fell: same
## uid, new id, instance values intact, and edible again.
func _a_dead_carrier_puts_back_what_it_carried() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHealthSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsPickupSystem.new()) \
		.add(EcsDropSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var spot := Vector2(-21000.0, 0.0)
	var monkey := _manager.spawn(_world, _catalog, &"monkey", spot)
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent
	bag.capacity = 2
	# Two berries put in the bag, one with an instance value.
	var uids: Array[String] = []
	for i in 2:
		var berry := _manager.spawn(_world, _catalog, &"berry", spot + Vector2(0.0, 5000.0 + i * 100.0))
		if i == 0:
			(_world.get_component(berry, EcsConsumableComponent) as EcsConsumableComponent).nutrition = 41.0
		uids.append((_world.get_component(berry, EcsNameComponent) as EcsNameComponent).uid)
		bag.items.append(EcsItemRecord.capture(_world, berry))
		_world.add(berry, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("the carried berries are no longer entities", _ids_with_uids(uids).is_empty())

	# Death by health: the ordinary route, not a flag raised by the test.
	(_world.get_component(monkey, EcsHealthComponent) as EcsHealthComponent).value = 0.0
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("the carrier is flagged to die", _world.has(monkey, EcsDyingFlag))
	_check("and its bag was emptied onto the lifecycle inbox", bag.items.is_empty())

	living.run_all(_world, TICK)
	await get_tree().physics_frame
	var back := _ids_with_uids(uids)
	_check("the carrier is gone", not _world.is_alive(monkey))
	_check("both berries are back, as themselves (same uids)", back.size() == 2)
	var at_spot := true
	var drawn := true
	var kept_value := false
	for id: int in back:
		var place := _world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		at_spot = at_spot and place.position.is_equal_approx(spot)
		drawn = drawn and _manager.container_for(id) != null
		var food := _world.get_component(id, EcsConsumableComponent) as EcsConsumableComponent
		if is_equal_approx(food.nutrition, 41.0):
			kept_value = true
	_check("where the carrier fell, stacked on one spot", at_spot)
	_check("with nodes built for them", drawn)
	_check("and the instance value survived the round trip", kept_value)
	_check("none came back still flagged to die",
		back.all(func(id: int) -> bool: return not _world.has(id, EcsDyingFlag)))

	# Real again: a hungry grazer eats one off the ground.
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(0.0, 30.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.eat_below - 5.0
	var before := hunger.fullness
	var ate := false
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if _ids_with_uids(uids).size() < 2:
			ate = true
			break
	_check("a hungry grazer eats a dropped berry", ate and hunger.fullness > before)

	for id in _ids_with_uids(uids) + [rabbit]:
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)

## The live entities whose uid is one of `uids`.
func _ids_with_uids(uids: Array[String]) -> Array[int]:
	var found: Array[int] = []
	for id in _world.query([EcsNameComponent]):
		if uids.has((_world.get_component(id, EcsNameComponent) as EcsNameComponent).uid):
			found.append(id)
	return found

## Animals start with different energy, rolled from the blueprint's range,
## including runtime spawns.
func _animals_of_one_kind_start_differently_rested() -> void:
	var rolling := EcsScheduler.new()
	rolling.add(EcsEnergySystem.new())
	var spawned: Array[int] = []
	for i in 8:
		spawned.append(_manager.spawn(_world, _catalog, &"rabbit", Vector2(-24000.0, i * 200.0)))
	rolling.run_all(_world, 0.0)

	var values := {}
	var in_range := true
	for id in spawned:
		var energy := _world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		values[snappedf(energy.value, 0.01)] = true
		in_range = in_range and energy.value >= energy.max_energy * energy.start_min - 0.001 \
			and energy.value <= energy.max_energy * energy.start_max + 0.001
	_check("rabbits start at different energy (%d distinct of 8)" % values.size(),
		values.size() > 1)
	_check("all within the blueprint's authored range", in_range)

	var first := _world.get_component(spawned[0], EcsEnergyComponent) as EcsEnergyComponent
	var once := first.value
	rolling.run_all(_world, 0.0)
	_check("and it is rolled once, not every tick", is_equal_approx(first.value, once))

	for id in spawned:
		_world.add(id, EcsDyingFlag.new())
	_scheduler.run_all(_world, TICK)

## A stage run every third tick still simulates the same amount (delta is
## banked), and `phase` delays its first run.
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

## Well fed heals, starving hurts, and the band between does neither.
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

	# Between zero and `heal_above`: no change.
	hunger.fullness = hunger.heal_above * 0.5
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

## Awake drains, moving drains more, low energy leads to sleep, sleep restores
## up to `wake_at`.
func _it_tires_sleeps_and_wakes_rested() -> void:
	var living := EcsScheduler.new()
	living.add(EcsEnergySystem.new()).add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-9000.0, 0.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true  # the test sets energy by hand; no start roll
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

	# Walking costs more; set velocity as movement would.
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

	# Starving wakes a voluntary sleeper.
	energy.value = energy.rest_at - 1.0
	living.run_all(_world, TICK)
	_check("it sleeps again when tired", brain.state == EcsLowBrainComponent.State.SLEEP)
	hunger.fullness = 0.0
	living.run_all(_world, TICK)
	_check("but starving wakes it", brain.state != EcsLowBrainComponent.State.SLEEP)

## Collapse at zero: damage once, locked down until `collapse_release`, then an
## ordinary sleeper.
func _running_out_of_energy_drops_it_once() -> void:
	var living := EcsScheduler.new()
	living.add(EcsEnergySystem.new()).add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-9000.0, 2000.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true  # the test sets energy by hand; no start roll
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

	# No health: it collapses with no damage.
	_world.remove(rabbit, EcsHealthComponent)
	_world.remove(rabbit, EcsCollapsedFlag)
	energy.value = 0.0
	living.run_all(_world, TICK)
	_check("an entity with no health collapses without error",
		_world.has(rabbit, EcsCollapsedFlag))

## Without EcsEnergyComponent nothing tires or sleeps.
func _a_thing_with_no_energy_never_sleeps() -> void:
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-9000.0, 4000.0))
	await _tick(1)
	_check("a berry carries no energy", not _world.has(berry, EcsEnergyComponent))
	_check("and never collapses", not _world.has(berry, EcsCollapsedFlag))

## Food outranks rest: a tired creature goes for food it sees, and only a
## collapse cuts that trip short.
func _food_outranks_rest_and_a_trip_is_not_cut_short() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsEnergySystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new())

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-11000.0, 0.0))
	var berry := _manager.spawn(_world, _catalog, &"berry", Vector2(-10850.0, 0.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true  # the test sets energy by hand; no start roll
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

## Sleepers and collapsed entities still get hungry, at `asleep_drain_scale`.
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

## An attack intent hits a target in reach for damage less armour, once per
## interval; a crit multiplies it; enough hits kill through EcsHealthSystem.
func _a_hit_lands_less_armour_on_cooldown_and_can_crit() -> void:
	var fighting := EcsScheduler.new()
	fighting \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsAttackSystem.new()) \
		.add(EcsCritSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsHealthSystem.new())

	var spot := Vector2(9000.0, 9000.0)
	var attacker := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var target := _manager.spawn(_world, _catalog, &"monkey", spot + Vector2(20.0, 0.0))
	var attack := EcsDamageComponent.new()
	attack.damage = 10.0
	attack.interval = 1.0
	_world.add(attacker, attack)
	var armor := EcsArmorComponent.new()
	armor.reduction = 3.0
	armor.minimum = 1.0
	_world.add(target, armor)
	var health := _world.get_component(target, EcsHealthComponent) as EcsHealthComponent

	var attack_intent := EcsAttackIntentFlag.new()
	attack_intent.target_id = target
	_world.add(attacker, attack_intent)
	for i in 3:
		fighting.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("a hit in reach lands for damage less armour", is_equal_approx(health.value, 93.0))

	for i in 30:
		fighting.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("and not again before the interval is up", is_equal_approx(health.value, 93.0))

	var crit := EcsCritChanceComponent.new()
	crit.chance = 1.0
	crit.multiplier = 2.0
	_world.add(attacker, crit)
	for i in 40:
		fighting.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("a crit doubles the hit before armour", is_equal_approx(health.value, 76.0))

	armor.reduction = 50.0
	attack.cooldown = 0.0
	fighting.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("armour never takes a hit below its minimum", is_equal_approx(health.value, 75.0))

	(_world.get_component(target, EcsPositionComponent) as EcsPositionComponent).position = spot + Vector2(400.0, 0.0)
	_manager.container_for(target).position = spot + Vector2(400.0, 0.0)
	for i in 3:
		await get_tree().physics_frame
	attack.cooldown = 0.0
	fighting.run_all(_world, TICK)
	_check("a target out of reach is not hit", is_equal_approx(health.value, 75.0))

	(_world.get_component(target, EcsPositionComponent) as EcsPositionComponent).position = spot + Vector2(20.0, 0.0)
	_manager.container_for(target).position = spot + Vector2(20.0, 0.0)
	armor.reduction = 0.0
	_world.remove(attacker, EcsCritChanceComponent)
	health.value = 15.0
	for i in 3:
		await get_tree().physics_frame
	attack.cooldown = 0.0
	fighting.run_all(_world, TICK)
	await get_tree().physics_frame
	attack.cooldown = 0.0
	fighting.run_all(_world, TICK)
	_check("two hits of 10 take 15 health to zero", health.value <= 0.0)
	_check("and EcsHealthSystem flags it dying", _world.has(target, EcsDyingFlag))
	var before := health.value
	attack.cooldown = 0.0
	fighting.run_all(_world, TICK)
	_check("a dying target is not hit again", is_equal_approx(health.value, before))

	_world.add(attacker, EcsDyingFlag.new())
	fighting.run_all(_world, TICK)
	await get_tree().physics_frame

## A creature that dies by health leaves a corpse holding its bag. A hungry
## carrier loots it, a plant-eater ignores the meat, a meat-eater eats it, and
## what the corpse still held is spilled.
func _death_by_health_leaves_a_corpse_to_loot_and_eat() -> void:
	var living := _corpse_pipeline(true)
	var spot := Vector2(-9000.0, 9000.0)
	var dead := _manager.spawn(_world, _catalog, &"monkey", spot)
	var dead_name := String((_world.get_component(dead, EcsNameComponent) as EcsNameComponent).entity_name)
	var bag := _world.get_component(dead, EcsInventoryComponent) as EcsInventoryComponent
	bag.capacity = 2
	var uids: Array[String] = []
	for i in 2:
		var berry := _manager.spawn(_world, _catalog, &"berry", spot + Vector2(0.0, 5000.0 + i * 100.0))
		uids.append((_world.get_component(berry, EcsNameComponent) as EcsNameComponent).uid)
		bag.items.append(EcsItemRecord.capture(_world, berry))
		_world.add(berry, EcsDyingFlag.new())
	(_world.get_component(dead, EcsHealthComponent) as EcsHealthComponent).value = 0.0
	for i in 2:
		living.run_all(_world, TICK)
		await get_tree().physics_frame

	var corpse := _first_of(&"corpse")
	_check("the creature is gone", not _world.is_alive(dead))
	_check("and a corpse is where it fell", corpse != EcsWorld.NO_ENTITY
		and (_world.get_component(corpse, EcsPositionComponent) as EcsPositionComponent).position.is_equal_approx(spot))
	_check("named for it", corpse != EcsWorld.NO_ENTITY
		and String((_world.get_component(corpse, EcsNameComponent) as EcsNameComponent).entity_name) == "corpse_of_" + dead_name)
	var held := _world.get_component(corpse, EcsInventoryComponent) as EcsInventoryComponent
	_check("holding the bag it carried", held != null and held.items.size() == 2
		and held.items.all(func(r: EcsItemRecord) -> bool: return uids.has(r.uid)))
	var body := _world.get_component(corpse, EcsBodyComponent) as EcsBodyComponent
	_check("the same size, and walked over", is_equal_approx(body.radius, 36.0) and not body.is_solid)
	_check("drawn darker than it was",
		(_world.get_component(corpse, EcsSpriteComponent) as EcsSpriteComponent).tint.v < 0.6)

	var looter := _manager.spawn(_world, _catalog, &"monkey", spot + Vector2(30.0, 0.0))
	var looter_hunger := _world.get_component(looter, EcsHungerComponent) as EcsHungerComponent
	looter_hunger.fullness = looter_hunger.forage_below - 10.0
	var grazer := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(0.0, 30.0))
	var grazer_hunger := _world.get_component(grazer, EcsHungerComponent) as EcsHungerComponent
	grazer_hunger.fullness = 10.0
	for i in 6:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	var loot := _world.get_component(looter, EcsInventoryComponent) as EcsInventoryComponent
	_check("a hungry carrier loots a record from the corpse", loot.items.size() == 1
		and uids.has(loot.items[0].uid) and held.items.size() == 1)
	_check("a plant-eater leaves the meat alone",
		_world.is_alive(corpse) and not _world.has(corpse, EcsDyingFlag))

	grazer_hunger.eats = &"meat"
	var before := grazer_hunger.fullness
	for i in 6:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("a meat-eater eats the corpse", not _world.is_alive(corpse) and grazer_hunger.fullness > before)
	_check("and what it still held is spilled, as itself", _ids_with_uids(uids).size() == 1)

	for id in _ids_with_uids(uids) + [looter, grazer]:
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## A corpse flags itself dying when its time is up, and spills its bag.
func _a_corpse_rots_and_spills_what_it_held() -> void:
	var living := _corpse_pipeline(false)
	var spot := Vector2(-9000.0, -9000.0)
	var corpse := _manager.spawn(_world, _catalog, &"corpse", spot)
	var berry := _manager.spawn(_world, _catalog, &"berry", spot + Vector2(0.0, 5000.0))
	var uids: Array[String] = [(_world.get_component(berry, EcsNameComponent) as EcsNameComponent).uid]
	(_world.get_component(corpse, EcsInventoryComponent) as EcsInventoryComponent).items.append(
		EcsItemRecord.capture(_world, berry))
	_world.add(berry, EcsDyingFlag.new())
	var rot := _world.get_component(corpse, EcsRotComponent) as EcsRotComponent
	living.run_all(_world, TICK)
	_check("a fresh corpse is not rotting away yet", not _world.has(corpse, EcsDyingFlag))

	rot.age = rot.lasts - TICK * 0.5
	living.run_all(_world, TICK)
	_check("it rots once its time is up", _world.has(corpse, EcsDyingFlag))
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	_check("and is gone, its berry back on the ground", not _world.is_alive(corpse)
		and _ids_with_uids(uids).size() == 1)
	for id in _ids_with_uids(uids):
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)

## A fed crocodile leaves prey alone. A hungry one hunts the nearest prey that
## is not its own kind, attacks it in reach, kills it, and eats the corpse.
func _a_hungry_hunter_kills_its_prey_and_eats_the_corpse() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHealthSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsCritSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsCorpseSystem.new()) \
		.add(EcsDropSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var spot := Vector2(9000.0, -9000.0)
	var hunter := _manager.spawn(_world, _catalog, &"crocodile", spot)
	var rival := _manager.spawn(_world, _catalog, &"crocodile", spot + Vector2(-90.0, 0.0))
	var prey := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(200.0, 0.0))
	# Remove the brains of the rival and the prey so only the hunter acts.
	_world.remove(rival, EcsLowBrainComponent)
	_world.remove(prey, EcsLowBrainComponent)
	var brain := _world.get_component(hunter, EcsLowBrainComponent) as EcsLowBrainComponent
	var hunger := _world.get_component(hunter, EcsHungerComponent) as EcsHungerComponent

	hunger.fullness = 90.0
	var hunted := false
	for i in 30:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		hunted = hunted or brain.state == EcsLowBrainComponent.State.HUNT
	_check("a fed hunter leaves prey alone", not hunted)

	hunger.fullness = 30.0
	var chased_prey := false
	var chased_rival := false
	var attacked := false
	var flag_matches := true
	var corpse := EcsWorld.NO_ENTITY
	for i in 900:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.HUNT:
			chased_prey = chased_prey or brain.target == prey
			chased_rival = chased_rival or brain.target == rival
		attacked = attacked or brain.state == EcsLowBrainComponent.State.ATTACK
		flag_matches = flag_matches and (_world.has(hunter, EcsAttackIntentFlag)
			== (brain.state == EcsLowBrainComponent.State.ATTACK))
		if corpse == EcsWorld.NO_ENTITY:
			corpse = _first_of(&"corpse")
		elif not _world.is_alive(corpse):
			break
	_check("a hungry hunter chases the prey", chased_prey)
	_check("and never its own kind, though it is nearer", not chased_rival)
	_check("it attacks once the prey is in reach", attacked)
	_check("the attack flag is raised exactly while it attacks", flag_matches)
	_check("the prey is killed", not _world.is_alive(prey))
	_check("and the hunter eats the corpse", corpse != EcsWorld.NO_ENTITY
		and not _world.is_alive(corpse) and hunger.fullness > 30.0)

	_world.add(hunter, EcsDyingFlag.new())
	_world.add(rival, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	var leftover := _first_of(&"corpse")
	while leftover != EcsWorld.NO_ENTITY:
		_world.add(leftover, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		leftover = _first_of(&"corpse")

func _corpse_pipeline(with_brain: bool) -> EcsScheduler:
	var living := EcsScheduler.new()
	living.add(EcsLifecycleSystem.new(_manager, _catalog))
	living.add(EcsHealthSystem.new())
	living.add(EcsSensorSystem.new(_manager))
	if with_brain:
		living.add(EcsLowBrainSystem.new())
	living.add(EcsConsumeSystem.new())
	living.add(EcsPickupSystem.new())
	living.add(EcsRotSystem.new())
	living.add(EcsCorpseSystem.new())
	living.add(EcsDropSystem.new())
	return living

## Raises an intent flag, standing in for the brain.
func _intend_take(id: int, target: int) -> void:
	var take := EcsTakeIntentFlag.new()
	take.target_id = target
	_world.add(id, take)

func _intend_eat(id: int, target: int) -> void:
	var eat := EcsEatIntentFlag.new()
	eat.target_id = target
	_world.add(id, eat)

## Does `bag` hold a record of entity `id`? Matched by uid, remembered while alive.
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

## A view rebuilds after any structural change to a table it names, and only then.
func _a_view_is_kept_until_a_table_it_names_changes() -> void:
	var world := EcsWorld.new()
	var a := world.create_entity()
	var b := world.create_entity()
	world.add(a, EcsPositionComponent.new())
	world.add(a, EcsMovementComponent.new())
	world.add(b, EcsPositionComponent.new())
	var include := [EcsPositionComponent, EcsMovementComponent]

	var first := world.view(include)
	_check("a view holds what query() returns", first.ids == world.query(include))
	_check("with each component beside its id",
		first.column(EcsMovementComponent)[0] == world.get_component(a, EcsMovementComponent))
	_check("asked again with nothing changed, it is the same view", world.view(include) == first)

	world.add(a, EcsHungerComponent.new())
	_check("a change to a table it does not name leaves it alone", world.view(include) == first)

	world.add(b, EcsMovementComponent.new())
	var grown := world.view(include)
	_check("an entity gaining a named type rebuilds it", grown != first and grown.ids.size() == 2)
	_check("and the old one is left as it was, for anyone still walking it", first.ids.size() == 1)

	var fresh_move := EcsMovementComponent.new()
	world.add(a, fresh_move)
	_check("a replaced component is the one the column hands out",
		world.view(include).column(EcsMovementComponent).has(fresh_move))

	world.destroy_entity(b)
	_check("a death rebuilds it without the dead", world.view(include).ids == [a])

	world.add(a, EcsDyingFlag.new())
	_check("an excluded flag being raised rebuilds it",
		world.view(include, [EcsDyingFlag]).ids.is_empty())
	world.remove(a, EcsDyingFlag)
	_check("and being cleared rebuilds it again", world.view(include, [EcsDyingFlag]).ids == [a])

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[test] %s  %s" % ["PASS" if passed else "FAIL", what])
