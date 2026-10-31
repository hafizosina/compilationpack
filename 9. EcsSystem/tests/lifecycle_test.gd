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
	await _a_bush_yields_only_when_harvested()
	await _hungry_plant_eaters_harvest_then_eat_or_take()
	_the_planner_finds_the_cheapest_chain()
	await _power_and_diet_decide_who_hunts_whom()
	await _utility_picks_what_the_ladder_would()
	await _a_planned_hunter_kills_once_and_eats_the_corpse()
	await _planned_plant_eaters_harvest_then_eat_or_take()
	await _replans_follow_events_not_the_clock()
	await _hunger_and_danger_are_weighed_both_ways()
	await _a_rabbit_flees_what_could_hunt_it()
	await _skills_start_end_and_cool()
	await _a_hidden_hunter_is_noticed_late()
	_the_ambush_is_planned_by_cost()
	await _an_ambush_gives_up_after_its_patience()
	await _a_crocodile_ambushes_from_the_water()
	await _thirst_drains_and_dehydration_kills()
	await _drinking_needs_drinkable_water_in_reach()
	await _a_thirsty_animal_drinks_and_thirst_is_weighed_against_hunger()
	_thirst_is_planned_and_weighed()
	await _thirsty_prey_walk_into_an_ambush()
	await _skills_come_from_one_default_set()
	await _what_a_hunter_does_comes_from_its_stats()
	await _each_kind_hides_in_its_own_cover()
	await _hidden_prey_is_passed_over()
	await _prey_stay_safe_by_hiding_or_escaping()
	await _prey_scan_before_drinking()
	await _memory_learns_fades_and_is_proven_wrong()
	await _a_remembered_place_is_planned_and_walked_to()
	await _fear_and_traffic_price_places()
	await _memory_keeps_what_matters_to_it()
	_a_stun_holds_still_and_wears_off()
	_hunted_prey_cannot_hide()
	await _a_pounce_stuns_and_bites_follow_until_dead()

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
	# Bushes are harvested now, so the test gives one a spawner.
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", Vector2(-800.0, -400.0))
	var spawner := EcsSpawnerComponent.new()
	spawner.radius = 300.0
	_world.add(bush, spawner)

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

## A walker is pushed out of a solid immovable body (a bush made solid), and the body
## doesn't move.
func _an_immovable_body_is_not_shoved_around() -> void:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(-2000.0, -2000.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", Vector2(-1990.0, -2000.0))
	(_world.get_component(bush, EcsBodyComponent) as EcsBodyComponent).is_solid = true
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
	var wall := _manager.spawn(_world, _catalog, &"berry_bush", bush_at)
	(_world.get_component(wall, EcsBodyComponent) as EcsBodyComponent).is_solid = true
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

	hunger.fullness = hunger.max_fullness
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

## A bush makes nothing on its own. Harvesting takes one unit per `harvest_time`
## and drops a berry in the harvester's reach; an empty bush yields nothing, and
## stock regrows.
func _a_bush_yields_only_when_harvested() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsHarvestSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))

	var spot := Vector2(-12000.0, 6000.0)
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot)
	var crop := _world.get_component(bush, EcsHarvestableComponent) as EcsHarvestableComponent
	for i in 120:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("an unharvested bush makes no berry", _berries_near(spot, 300.0).is_empty())
	_check("and starts full", crop.stock == crop.stock_max)

	var monkey := _manager.spawn(_world, _catalog, &"monkey", spot + Vector2(85.0, 0.0))
	_world.remove(monkey, EcsLowBrainComponent)
	var harvest := EcsHarvestIntentFlag.new()
	harvest.target_id = bush
	_world.add(monkey, harvest)
	var unit_ticks := ceili(crop.harvest_time / TICK)
	for i in unit_ticks + 3:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	var action := _world.get_component(monkey, EcsActionComponent) as EcsActionComponent
	var first := _berries_near(spot, 300.0)
	_check("one harvest takes one unit", crop.stock == crop.stock_max - 1)
	_check("and drops one berry", first.size() == 1)
	_check("in the harvester's reach", first.size() == 1 and action.reached.has(first[0]))

	for i in unit_ticks * (crop.stock_max + 2):
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("an emptied bush has yielded exactly its stock",
		crop.stock == 0 and _berries_near(spot, 300.0).size() == crop.stock_max)

	_world.remove(monkey, EcsHarvestIntentFlag)
	crop.regrow_left = 0.1
	for i in 10:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("and it regrows", crop.stock == 1)

	for id in [bush, monkey] + _berries_near(spot, 300.0):
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## A hungry rabbit walks to a bush, harvests and eats the berry off the ground; a
## hungry monkey harvests and pockets it. The harvest flag matches the state.
func _hungry_plant_eaters_harvest_then_eat_or_take() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsHarvestSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit_spot := Vector2(-12000.0, -6000.0)
	var monkey_spot := Vector2(-12000.0, -9000.0)
	var bushes: Array[int] = [
		_manager.spawn(_world, _catalog, &"berry_bush", rabbit_spot),
		_manager.spawn(_world, _catalog, &"berry_bush", monkey_spot),
	]
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", rabbit_spot + Vector2(220.0, 0.0))
	var monkey := _manager.spawn(_world, _catalog, &"monkey", monkey_spot + Vector2(220.0, 0.0))
	var creatures: Array[int] = [rabbit, monkey]
	for id in creatures:
		var energy := _world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true  # the test sets energy by hand; no start roll
		energy.value = energy.max_energy
	var rabbit_hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	rabbit_hunger.fullness = rabbit_hunger.forage_below - 1.0
	var rabbit_started := rabbit_hunger.fullness
	var monkey_hunger := _world.get_component(monkey, EcsHungerComponent) as EcsHungerComponent
	monkey_hunger.fullness = monkey_hunger.forage_below - 1.0
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent

	var harvested := {}
	var monkey_ate := false
	var flag_matches := true
	for i in 600:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		for id in creatures:
			var brain := _world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
			var harvesting := brain.state == EcsLowBrainComponent.State.HARVEST
			harvested[id] = harvested.get(id, false) or harvesting
			flag_matches = flag_matches and _world.has(id, EcsHarvestIntentFlag) == harvesting
		monkey_ate = monkey_ate or _world.has(monkey, EcsEatIntentFlag)
		if rabbit_hunger.fullness > rabbit_started and not bag.items.is_empty():
			break
	_check("a hungry rabbit harvests a bush", harvested.get(rabbit, false))
	_check("and eats what it harvested", rabbit_hunger.fullness > rabbit_started)
	_check("a hungry monkey harvests a bush", harvested.get(monkey, false))
	_check("and pockets what it harvested, without eating", not bag.items.is_empty()
		and not monkey_ate)
	_check("the harvest flag is raised exactly while it harvests", flag_matches)

	for id in creatures + bushes + _berries_near(rabbit_spot, 400.0) \
			+ _berries_near(monkey_spot, 400.0):
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## The planner over the authored actions: shortest chains for each need, the
## meat chain through a kill, and [] when nothing reaches the goal.
func _the_planner_finds_the_cheapest_chain() -> void:
	var all := _actions([&"eat_carried", &"eat_ground", &"take", &"loot", &"seek_food",
		&"seek_bush", &"harvest", &"hunt", &"attack", &"sleep"])
	var rabbit := _actions([&"eat_ground", &"seek_food", &"seek_bush", &"harvest", &"sleep"])
	var monkey := _actions([&"eat_carried", &"eat_ground", &"take", &"loot", &"seek_food",
		&"seek_bush", &"harvest", &"sleep"])
	var croc := _actions([&"eat_ground", &"seek_food", &"hunt", &"attack", &"sleep"])
	var fed := {&"fed": true}
	var bagged := {&"has_room": false}
	_check("food in the bag: eat it",
		EcsPlanner.plan({&"food_in_bag": true, &"food_in_reach": true}, fed, all)
			== [&"eat_carried"])
	_check("food in reach: eat it off the ground",
		EcsPlanner.plan({&"food_in_reach": true}, fed, all) == [&"eat_ground"])
	_check("food in sight: walk to it, then eat",
		EcsPlanner.plan({&"food_in_sight": true}, fed, rabbit) == [&"seek_food", &"eat_ground"])
	_check("provisioning: walk to it, then take it",
		EcsPlanner.plan({&"food_in_sight": true, &"has_room": true}, bagged, monkey)
			== [&"seek_food", &"take"])
	_check("a bush in sight: walk, harvest, eat",
		EcsPlanner.plan({&"bush_in_sight": true}, fed, rabbit)
			== [&"seek_bush", &"harvest", &"eat_ground"])
	_check("a carrier harvests to provision",
		EcsPlanner.plan({&"bush_in_sight": true, &"has_room": true}, bagged, monkey)
			== [&"seek_bush", &"harvest", &"take"])
	_check("prey in sight: hunt, kill, then eat what the kill leaves",
		EcsPlanner.plan({&"prey_in_sight": true}, fed, croc)
			== [&"hunt", &"attack", &"seek_food", &"eat_ground"])
	_check("a plant-eater has no plan for prey", EcsPlanner.plan({&"prey_in_sight": true},
		fed, rabbit).is_empty())
	_check("rest is a plan of one", EcsPlanner.plan({}, {&"rested": true}, all) == [&"sleep"])
	_check("but not while starving",
		EcsPlanner.plan({&"starving": true}, {&"rested": true}, all).is_empty())
	_check("nothing in sight: no plan", EcsPlanner.plan({}, fed, all).is_empty())
	_check("a threat near: flee", EcsPlanner.plan({&"threat_near": true}, {&"safe": true},
		_actions([&"flee"])) == [&"flee"])

## Diet and power decide hunting: no prey tag, no blueprint check.
func _power_and_diet_decide_who_hunts_whom() -> void:
	var spot := Vector2(15000.0, 15000.0)
	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot)
	var big := _manager.spawn(_world, _catalog, &"crocodile", spot + Vector2(400.0, 0.0))
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(800.0, 0.0))
	var monkey := _manager.spawn(_world, _catalog, &"monkey", spot + Vector2(1200.0, 0.0))
	_check("power is authored per kind", EcsHunting.power_of(_world, croc)
		> EcsHunting.power_of(_world, monkey)
		and EcsHunting.power_of(_world, monkey) > EcsHunting.power_of(_world, rabbit))
	_check("a crocodile can hunt a rabbit and a monkey",
		EcsHunting.can_hunt(_world, croc, rabbit) and EcsHunting.can_hunt(_world, croc, monkey))
	_check("a plant-eater hunts nothing", not EcsHunting.can_hunt(_world, monkey, rabbit))
	_check("an equal is not prey", not EcsHunting.can_hunt(_world, croc, big))
	(_world.get_component(big, EcsHealthComponent) as EcsHealthComponent).power = 100.0
	_check("a stronger crocodile hunts a weaker one", EcsHunting.can_hunt(_world, big, croc)
		and not EcsHunting.can_hunt(_world, croc, big))
	_check("and is a threat to it", EcsHunting.threatens(_world, big, croc))
	_world.add(rabbit, EcsDyingFlag.new())
	_check("the dying are not prey", not EcsHunting.can_hunt(_world, croc, rabbit))
	for id in [croc, big, monkey]:
		_world.add(id, EcsDyingFlag.new())
	await _tick(1)

## With no danger, the top-scoring goal is the ladder's rung, over a grid of
## fullness and energy for each kind.
func _utility_picks_what_the_ladder_would() -> void:
	var planning := EcsPlanningSystem.new()
	for kind in [&"rabbit", &"monkey", &"crocodile"]:
		var id := _manager.spawn(_world, _catalog, kind, Vector2(16000.0, -16000.0))
		var hunger := _world.get_component(id, EcsHungerComponent) as EcsHungerComponent
		var energy := _world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		var carrier := _world.has(id, EcsInventoryComponent)
		var mismatches := 0
		for f in range(0, 101, 5):
			for e in range(0, 101, 10):
				hunger.fullness = f
				energy.value = e
				var expected := &""
				if f <= minf(hunger.eat_below, hunger.forage_below):
					expected = &"satisfy_hunger"
				elif carrier and f <= hunger.forage_below:
					expected = &"provision"
				elif e <= energy.rest_at:
					expected = &"rest"
				var ranked := planning.rank(_world, id)
				var top: StringName = ranked[0].id if not ranked.is_empty() else &""
				if top != expected:
					mismatches += 1
		_check("%s: utility picks the ladder's rung (%d mismatches)" % [kind, mismatches],
			mismatches == 0)
		_world.add(id, EcsDyingFlag.new())
	await _tick(1)

## A planned wild dog hunts, kills and eats the corpse, killing once per meal,
## with no "food in sight ends a hunt" rule on its path.
func _a_planned_hunter_kills_once_and_eats_the_corpse() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHealthSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
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

	var spot := Vector2(9000.0, 9000.0)
	var hunter := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var prey: Array[int] = [
		_manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(200.0, 0.0)),
		_manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(-220.0, 60.0)),
	]
	for id in prey:
		_world.remove(id, EcsLowBrainComponent)
	var energy := _world.get_component(hunter, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true  # the test sets energy by hand; no start roll
	energy.value = energy.max_energy
	var hunger := _world.get_component(hunter, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = 30.0
	var planner := _world.get_component(hunter, EcsPlannerComponent) as EcsPlannerComponent

	var planned_kill := false
	var ate := false
	var flag_matches := true
	for i in 900:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		var brain := _world.get_component(hunter, EcsLowBrainComponent) as EcsLowBrainComponent
		planned_kill = planned_kill or (planner.steps.has(&"attack")
			and planner.steps.has(&"eat_ground") and planner.goal == &"satisfy_hunger")
		flag_matches = flag_matches and (_world.has(hunter, EcsAttackIntentFlag)
			== (brain.state == EcsLowBrainComponent.State.ATTACK))
		if hunger.fullness > 30.0:
			ate = true
			break
	var alive := prey.filter(func(id: int) -> bool: return _world.is_alive(id)).size()
	_check("the planner chose kill then eat", planned_kill)
	_check("the hunter ate", ate)
	_check("after one kill, not two (%d of 2 prey left)" % alive, alive == 1)
	_check("the attack flag is raised exactly while it attacks", flag_matches)

	for id in [hunter] + prey:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	var leftover := _first_of(&"corpse")
	while leftover != EcsWorld.NO_ENTITY:
		_world.add(leftover, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		leftover = _first_of(&"corpse")

## The harvest chain, planned: the rabbit's plan ends in eat_ground, the monkey's
## in take, and both end fed or provisioned.
func _planned_plant_eaters_harvest_then_eat_or_take() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsHarvestSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsPickupSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))

	var rabbit_spot := Vector2(-15000.0, -6000.0)
	var monkey_spot := Vector2(-15000.0, -9000.0)
	var bushes: Array[int] = [
		_manager.spawn(_world, _catalog, &"berry_bush", rabbit_spot),
		_manager.spawn(_world, _catalog, &"berry_bush", monkey_spot),
	]
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", rabbit_spot + Vector2(220.0, 0.0))
	var monkey := _manager.spawn(_world, _catalog, &"monkey", monkey_spot + Vector2(220.0, 0.0))
	var creatures: Array[int] = [rabbit, monkey]
	for id in creatures:
		var energy := _world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true  # the test sets energy by hand; no start roll
		energy.value = energy.max_energy
	var rabbit_hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	rabbit_hunger.fullness = rabbit_hunger.forage_below - 1.0
	var rabbit_started := rabbit_hunger.fullness
	var monkey_hunger := _world.get_component(monkey, EcsHungerComponent) as EcsHungerComponent
	monkey_hunger.fullness = monkey_hunger.forage_below - 1.0
	var bag := _world.get_component(monkey, EcsInventoryComponent) as EcsInventoryComponent
	var rabbit_plan := _world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent
	var monkey_plan := _world.get_component(monkey, EcsPlannerComponent) as EcsPlannerComponent

	var plans := {}
	var flag_matches := true
	for i in 600:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		plans[" > ".join(rabbit_plan.steps)] = true
		plans[" > ".join(monkey_plan.steps)] = true
		for id in creatures:
			var brain := _world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
			flag_matches = flag_matches and _world.has(id, EcsHarvestIntentFlag) \
				== (brain.state == EcsLowBrainComponent.State.HARVEST) \
				and _world.has(id, EcsEatIntentFlag) == (brain.state == EcsLowBrainComponent.State.EAT) \
				and _world.has(id, EcsTakeIntentFlag) == (brain.state == EcsLowBrainComponent.State.TAKE)
		if rabbit_hunger.fullness > rabbit_started and not bag.items.is_empty():
			break
	_check("the rabbit planned walk, harvest, eat", plans.has("seek_bush > harvest > eat_ground"))
	_check("and ate", rabbit_hunger.fullness > rabbit_started)
	_check("the monkey planned walk, harvest, take", plans.has("seek_bush > harvest > take"))
	_check("and pocketed it", not bag.items.is_empty())
	_check("flags and state agreed on every tick", flag_matches)

	for id in creatures + bushes + _berries_near(rabbit_spot, 400.0) \
			+ _berries_near(monkey_spot, 400.0):
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## A creature whose facts and needs hold still is not replanned; a change to
## either replans it once; no run plans more than MAX_REPLANS.
func _replans_follow_events_not_the_clock() -> void:
	var planning := EcsPlanningSystem.new()
	var spot := Vector2(-16000.0, 16000.0)
	var croc := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var energy := _world.get_component(croc, EcsEnergyComponent) as EcsEnergyComponent
	energy.value = energy.max_energy
	var hunger := _world.get_component(croc, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.max_fullness
	var planner := _world.get_component(croc, EcsPlannerComponent) as EcsPlannerComponent
	for i in 100:
		planning.run(_world, TICK)
	_check("a settled creature plans once (%d)" % planner.replans, planner.replans == 1)
	hunger.fullness = 20.0
	for i in 100:
		planning.run(_world, TICK)
	_check("a need crossing its gate replans it once (%d)" % planner.replans,
		planner.replans == 2)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(250.0, 0.0))
	(_world.get_component(croc, EcsSensorComponent) as EcsSensorComponent).perceived.append(rabbit)
	for i in 100:
		planning.run(_world, TICK)
	_check("prey coming into sight replans it once (%d)" % planner.replans,
		planner.replans == 3)
	_check("into a hunt", planner.steps.size() > 0 and planner.steps[0] == &"hunt")
	_world.add(croc, EcsDyingFlag.new())
	_world.add(rabbit, EcsDyingFlag.new())

	var crowd: Array[int] = []
	for i in EcsPlanningSystem.MAX_REPLANS + 10:
		crowd.append(_manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(i * 60.0, 900.0)))
	planning.run(_world, TICK)
	var first := crowd.filter(func(id: int) -> bool:
		return (_world.get_component(id, EcsPlannerComponent) as EcsPlannerComponent).planned).size()
	planning.run(_world, TICK)
	var second := crowd.filter(func(id: int) -> bool:
		return (_world.get_component(id, EcsPlannerComponent) as EcsPlannerComponent).planned).size()
	_check("one run plans at most MAX_REPLANS (%d)" % first,
		first == EcsPlanningSystem.MAX_REPLANS)
	_check("and the rest wait their turn (%d)" % second, second == crowd.size())
	for id in crowd:
		_world.add(id, EcsDyingFlag.new())
	await _tick(1)

## Starving outranks danger; merely hungry or fed, danger wins.
func _hunger_and_danger_are_weighed_both_ways() -> void:
	var planning := EcsPlanningSystem.new()
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", Vector2(17000.0, -17000.0))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
	var top := func() -> StringName:
		var ranked := planning.rank(_world, rabbit)
		return ranked[0].id if not ranked.is_empty() else &""
	danger.value = 1.0
	hunger.fullness = 0.0
	_check("starving, it keeps after food", top.call() == &"satisfy_hunger")
	hunger.fullness = hunger.forage_below - 5.0
	_check("merely hungry, it flees", top.call() == &"flee")
	hunger.fullness = hunger.max_fullness
	danger.value = danger.flee_at
	_check("fed, any danger past the gate sends it off", top.call() == &"flee")
	danger.value = danger.flee_at - 0.01
	_check("below the gate danger doesn't count", top.call() == &"")
	_world.add(rabbit, EcsDyingFlag.new())
	await _tick(1)

## A rabbit that sees a crocodile fills with danger and runs; with the threat
## gone the danger decays and it stops. A sleeper wakes to flee, and a bite
## from something unseen is enough.
func _a_rabbit_flees_what_could_hunt_it() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsEnergySystem.new()) \
		.add(EcsDangerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))

	var bounds := EcsConst.world_bounds
	var spot := Vector2(20000.0, 0.0)
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(200.0, 0.0))
	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot)
	_world.remove(croc, EcsLowBrainComponent)
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true  # the test sets energy by hand; no start roll
	energy.value = energy.max_energy
	var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var planner := _world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent
	var at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var croc_at := (_world.get_component(croc, EcsPositionComponent) as EcsPositionComponent).position

	var fled := false
	for i in 120:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		fled = fled or brain.state == EcsLowBrainComponent.State.FLEE
	_check("seeing a crocodile fills its danger (%.2f)" % danger.value,
		danger.value >= danger.flee_at)
	_check("and it flees", fled and planner.goal == &"flee")
	_check("away from it (%.0f px)" % at.position.distance_to(croc_at),
		at.position.distance_to(croc_at) > 400.0)

	_world.add(croc, EcsDyingFlag.new())
	for i in 600:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if danger.value <= 0.0:
			break
	_check("with the threat gone danger decays", danger.value <= 0.0)
	_check("and it stops fleeing", planner.goal != &"flee"
		and brain.state != EcsLowBrainComponent.State.FLEE)

	energy.value = energy.rest_at - 1.0
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	var slept := brain.state == EcsLowBrainComponent.State.SLEEP
	var wolf := _manager.spawn(_world, _catalog, &"crocodile", at.position + Vector2(150.0, 0.0))
	_world.remove(wolf, EcsLowBrainComponent)
	var woke := false
	for i in 90:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		woke = woke or brain.state == EcsLowBrainComponent.State.FLEE
	_check("a sleeper wakes to flee", slept and woke and not _world.has(rabbit, EcsAsleepFlag))
	_world.add(wolf, EcsDyingFlag.new())
	for i in 600:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if danger.value <= 0.0 and planner.goal != &"flee":
			break

	energy.value = energy.max_energy
	var biter := _manager.spawn(_world, _catalog, &"crocodile", at.position + Vector2(1500.0, 0.0))
	_world.remove(biter, EcsLowBrainComponent)
	var hit := EcsHit.new()
	hit.from = biter
	hit.to = rabbit
	hit.amount = 5.0
	(_world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton).hits.append(hit)
	var bitten := false
	for i in 30:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		bitten = bitten or brain.state == EcsLowBrainComponent.State.FLEE
	_check("a bite from something unseen raises danger", danger.value >= danger.flee_at
		and danger.threat == biter)
	_check("and sends it off", bitten)
	_check("the hurt flag is read and cleared", not _world.has(rabbit, EcsHurtFlag))

	for id in [rabbit, biter]:
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	EcsConst.world_bounds = bounds

## A skill starts on its intent, ends on time, is refused while cooling and is
## ready again after; hide holds only in cover and while asked for; dash scales
## speed; hiding restores energy at `hide_restore`.
func _skills_start_end_and_cool() -> void:
	var casting := EcsScheduler.new()
	casting \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsSkillSystem.new()) \
		.add(EcsEnergySystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var run := func(ticks: int) -> void:
		for i in ticks:
			casting.run_all(_world, TICK)
			await get_tree().physics_frame
	var spot := Vector2(-30000.0, 30000.0)

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	_world.remove(rabbit, EcsLowBrainComponent)
	_cast(rabbit, &"scan")
	await run.call(1)
	_check("a cast starts the skill", _world.has(rabbit, EcsScanningFlag))
	await run.call(100)
	_check("it ends after its duration", not _world.has(rabbit, EcsScanningFlag))
	await run.call(60)
	_check("still asked, it is refused while cooling", not _world.has(rabbit, EcsScanningFlag))
	_world.remove(rabbit, EcsCastIntentFlag)
	await run.call(480)
	_cast(rabbit, &"scan")
	await run.call(1)
	_check("and ready again after its cooldown", _world.has(rabbit, EcsScanningFlag))

	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot + Vector2(0.0, 2000.0))
	_world.remove(croc, EcsLowBrainComponent)
	var energy := _world.get_component(croc, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = 50.0
	_cast(croc, &"hide")
	await run.call(3)
	_check("hide is refused on land", not _world.has(croc, EcsHiddenFlag))
	var pond := _manager.spawn(_world, _catalog, &"water", _position_of(croc) + Vector2(150.0, 0.0))
	await run.call(3)
	_check("and holds in water", _world.has(croc, EcsHiddenFlag))
	var before := energy.value
	await run.call(60)
	_check("hiding restores energy at hide_restore (%.2f)" % (energy.value - before),
		absf(energy.value - before - energy.hide_restore) < 0.2)
	_world.remove(croc, EcsCastIntentFlag)
	await run.call(1)
	_check("a held skill ends when its intent is lifted", not _world.has(croc, EcsHiddenFlag))
	_cast(croc, &"hide")
	await run.call(2)
	(_world.get_component(croc, EcsPositionComponent) as EcsPositionComponent).position += Vector2(-800.0, 0.0)
	await run.call(3)
	_check("and when it leaves the water", not _world.has(croc, EcsHiddenFlag))
	_world.remove(croc, EcsCastIntentFlag)

	var move := _world.get_component(croc, EcsMovementComponent) as EcsMovementComponent
	move.destination = _position_of(croc) + Vector2(0.0, 3000.0)
	move.has_destination = true
	move.time_left = 0.0
	_cast(croc, &"dash")
	await run.call(2)
	var dashing := move.velocity.length()
	await run.call(60)
	var after := move.velocity.length()
	var dash := EcsSkillDef.find((_world.get_component(croc, EcsSkillsComponent) as EcsSkillsComponent).skills, &"dash") as EcsDashSkill
	_check("a dash scales speed (%.0f), then ends (%.0f)" % [dashing, after],
		is_equal_approx(dashing, move.speed * dash.speed_scale) and is_equal_approx(after, move.speed))

	for id in [rabbit, croc, pond]:
		_world.add(id, EcsDyingFlag.new())
	await run.call(1)

## A hidden crocodile goes unnoticed by an unaware watcher; an aware one notices
## it later than a plain one; a scanning one within its radius notices it like a
## plain one, and beyond it, or out of sight, scanning changes nothing.
func _a_hidden_hunter_is_noticed_late() -> void:
	var watching := EcsScheduler.new()
	watching \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsDangerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(30000.0, 0.0)

	var noticed_after := func(stealth: float, awareness: float, scan: float, gap: float) -> int:
		var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(gap, 0.0))
		var croc := _manager.spawn(_world, _catalog, &"crocodile", spot)
		_world.remove(rabbit, EcsLowBrainComponent)
		_world.remove(croc, EcsLowBrainComponent)
		if stealth > 0.0:
			var hidden := EcsHiddenFlag.new()
			hidden.stealth = stealth
			_world.add(croc, hidden)
		if scan > 0.0:
			var scanning := EcsScanningFlag.new()
			scanning.radius = scan
			_world.add(rabbit, scanning)
		(_world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent).awareness = awareness
		var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
		var ticks := 0
		while ticks < 600 and danger.value < danger.flee_at:
			watching.run_all(_world, TICK)
			await get_tree().physics_frame
			ticks += 1
		for id in [rabbit, croc]:
			_world.add(id, EcsDyingFlag.new())
		watching.run_all(_world, TICK)
		await get_tree().physics_frame
		return ticks
	var plain: int = await noticed_after.call(0.0, 0.0, 0.0, 200.0)
	var unseen: int = await noticed_after.call(0.95, 0.0, 0.0, 200.0)
	var aware: int = await noticed_after.call(0.95, 0.3, 0.0, 200.0)
	var scanned: int = await noticed_after.call(0.95, 0.0, 300.0, 200.0)
	var too_far: int = await noticed_after.call(0.95, 0.0, 100.0, 200.0)
	var out_of_sight: int = await noticed_after.call(0.95, 0.0, 600.0, 400.0)
	_check("an unaware watcher never notices a hidden crocodile (%d ticks)" % unseen, unseen >= 600)
	_check("an aware one does, later than a plain one (%d vs %d)" % [aware, plain],
		aware < 600 and aware >= plain * 2)
	_check("a scanning one within its radius, like a plain one (%d)" % scanned,
		absi(scanned - plain) <= 2)
	_check("beyond its radius scanning changes nothing (%d)" % too_far, too_far >= 600)
	_check("and it never reaches past what it perceives (%d)" % out_of_sight, out_of_sight >= 600)

## The crocodile's chains, pure: from land with water in sight it ambushes in
## six steps, under MAX_DEPTH; in the water it keeps ambushing though it sees
## prey; on land with prey in sight it chases; with nothing in sight, no plan.
func _the_ambush_is_planned_by_cost() -> void:
	var hunter := _actions([&"eat_ground", &"seek_food", &"hunt", &"attack", &"sleep", &"flee",
		&"go_to_lure", &"ambush", &"pounce", &"go_to_water", &"drink"])
	var fed := {&"fed": true}
	var slow := {&"hunt": INF}
	var ambush: Array[StringName] = [&"go_to_lure", &"ambush", &"pounce", &"attack",
		&"seek_food", &"eat_ground"]
	_check("a lure in sight: go to it and ambush",
		EcsPlanner.plan({&"lure_in_sight": true}, fed, hunter) == ambush)
	_check("at a lure, prey in sight, too slow to chase: keep ambushing",
		EcsPlanner.plan({&"in_cover": true, &"prey_come_here": true, &"prey_in_sight": true},
			fed, hunter, slow) == ambush.slice(1))
	_check("in cover that is no lure, prey in sight: chase",
		EcsPlanner.plan({&"in_cover": true, &"prey_in_sight": true}, fed, hunter)[0] == &"hunt")
	_check("fast enough, a lure and prey in sight: chase",
		EcsPlanner.plan({&"lure_in_sight": true, &"prey_in_sight": true}, fed, hunter,
			{&"hunt": 2.0}) == [&"hunt", &"attack", &"seek_food", &"eat_ground"])
	_check("too slow, a lure and prey in sight: ambush",
		EcsPlanner.plan({&"lure_in_sight": true, &"prey_in_sight": true}, fed, hunter, slow)
			== ambush)
	_check("prey close: pounce", EcsPlanner.plan({&"prey_close": true, &"prey_in_sight": true},
		fed, hunter)[0] == &"pounce")
	_check("nothing in sight: no plan", EcsPlanner.plan({}, fed, hunter).is_empty())

## An ambush no prey ever passes fails after `patience`: the crocodile leaves the
## water, then plans its way back.
func _an_ambush_gives_up_after_its_patience() -> void:
	var living := _ambush_pipeline()
	var spot := Vector2(-30000.0, -30000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot)
	var croc := _ambusher(spot + Vector2(320.0, 0.0))
	var planner := _world.get_component(croc, EcsPlannerComponent) as EcsPlannerComponent
	var brain := _world.get_component(croc, EcsLowBrainComponent) as EcsLowBrainComponent
	var patience := 0.0
	for action in planner.actions:
		if action.id == &"ambush":
			patience = action.patience
			action.patience = 2.0

	var ambushes := 0
	var hidden := false
	var left := false
	var was := brain.state
	for i in 900:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.AMBUSH and was != brain.state:
			ambushes += 1
		hidden = hidden or _world.has(croc, EcsHiddenFlag)
		left = left or (ambushes > 0 and EcsHunting.cover_of(_world, croc) <= 0.0
			and not _world.has(croc, EcsHiddenFlag))
		was = brain.state
		if ambushes >= 2:
			break
	_check("it ambushes hidden in the water", hidden)
	_check("out of patience it leaves", left)
	_check("and plans its way back (%d ambushes)" % ambushes, ambushes >= 2)

	for action in planner.actions:
		if action.id == &"ambush":
			action.patience = patience
	for id in [croc, pond]:
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	EcsConst.world_bounds = bounds

## A planned crocodile goes to water and ambushes. A monkey walking past is not
## chased while far; in dash reach it pounces once and bites. A kill is many attacks.
func _a_crocodile_ambushes_from_the_water() -> void:
	var living := _ambush_pipeline()
	var spot := Vector2(30000.0, -30000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot)
	var croc := _ambusher(spot + Vector2(320.0, 0.0))
	var brain := _world.get_component(croc, EcsLowBrainComponent) as EcsLowBrainComponent

	for i in 300:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.AMBUSH and _world.has(croc, EcsHiddenFlag):
			break
	_check("it goes to the water and ambushes, hidden",
		brain.state == EcsLowBrainComponent.State.AMBUSH and _world.has(croc, EcsHiddenFlag))
	var off := _position_of(croc).distance_to(spot)
	_check("in the middle of the pond (%d px off)" % roundi(off),
		off <= _radius_of(pond) * EcsLowBrainSystem.MIDDLE_SHARE)

	var at := _position_of(croc)
	var monkey := _manager.spawn(_world, _catalog, &"monkey", at + Vector2(120.0, -450.0))
	_world.remove(monkey, EcsLowBrainComponent)
	var walk := _world.get_component(monkey, EcsMovementComponent) as EcsMovementComponent
	walk.destination = at + Vector2(120.0, 450.0)
	walk.has_destination = true
	walk.time_left = 0.0
	var reach := EcsHunting.dash_reach(_world, croc)
	var health := _world.get_component(monkey, EcsHealthComponent) as EcsHealthComponent
	var whole := health.value
	var chased_far := false
	var dashes := 0
	var dashing := false
	for i in 1200:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if _world.is_alive(monkey) and _position_of(monkey).distance_to(_position_of(croc)) > reach + 30.0 \
				and dashes == 0:
			chased_far = chased_far or brain.state == EcsLowBrainComponent.State.HUNT \
				or brain.state == EcsLowBrainComponent.State.POUNCE
		var now := _world.has(croc, EcsDashingFlag)
		if now and not dashing:
			dashes += 1
		dashing = now
	_check("it keeps ambushing while the monkey is far", not chased_far)
	_check("in reach it pounces, once (%d)" % dashes, dashes == 1)
	_check("and bites it", not _world.is_alive(monkey) or health.value < whole)

	for id in [croc, pond, monkey]:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	var leftover := _first_of(&"corpse")
	while leftover != EcsWorld.NO_ENTITY:
		_world.add(leftover, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		leftover = _first_of(&"corpse")
	EcsConst.world_bounds = bounds

## Thirst drains, slower asleep; at zero it costs health, and a parched death
## leaves a corpse like any death by health.
func _thirst_drains_and_dehydration_kills() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsThirstSystem.new()) \
		.add(EcsHealthSystem.new()) \
		.add(EcsCorpseSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-30000.0, 9000.0)
	var awake := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var asleep := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(300.0, 0.0))
	_world.add(asleep, EcsAsleepFlag.new())
	var awake_thirst := _world.get_component(awake, EcsThirstComponent) as EcsThirstComponent
	var asleep_thirst := _world.get_component(asleep, EcsThirstComponent) as EcsThirstComponent
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	var lost := awake_thirst.max_hydration - awake_thirst.hydration
	_check("thirst drains at `drain` (%.2f)" % lost, absf(lost - awake_thirst.drain) < 0.05)
	_check("and slower asleep", asleep_thirst.max_hydration - asleep_thirst.hydration
		< lost * (asleep_thirst.asleep_drain_scale + 0.05))

	awake_thirst.hydration = 0.0
	var health := _world.get_component(awake, EcsHealthComponent) as EcsHealthComponent
	var before := health.value
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("dehydration costs health (%.1f)" % (before - health.value),
		absf(before - health.value - awake_thirst.dehydrate_damage) < 0.2)
	health.value = 1.0
	var corpse := EcsWorld.NO_ENTITY
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		corpse = _first_of(&"corpse")
		if corpse != EcsWorld.NO_ENTITY:
			break
	_check("a parched death leaves a corpse", not _world.is_alive(awake) and corpse != EcsWorld.NO_ENTITY)

	for id in [asleep, corpse]:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## A drink intent, with no brain, restores hydration only while drinkable water
## is in reach: not on land, not at cover that isn't drinkable.
func _drinking_needs_drinkable_water_in_reach() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsDrinkSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var run := func(ticks: int) -> void:
		for i in ticks:
			living.run_all(_world, TICK)
			await get_tree().physics_frame
	var spot := Vector2(30000.0, 9000.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	_world.remove(rabbit, EcsLowBrainComponent)
	var thirst := _world.get_component(rabbit, EcsThirstComponent) as EcsThirstComponent
	var pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(1000.0, 0.0))
	var dry := _manager.spawn(_world, _catalog, &"water", spot + Vector2(-1000.0, 0.0))
	_world.remove(dry, EcsDrinkableComponent)
	var drink := func(water: int) -> float:
		thirst.hydration = 20.0
		var intent := EcsDrinkIntentFlag.new()
		intent.target_id = water
		_world.add(rabbit, intent)
		await run.call(30)
		_world.remove(rabbit, EcsDrinkIntentFlag)
		return thirst.hydration - 20.0
	var place := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var on_land: float = await drink.call(pond)
	place.position = _position_of(dry) + Vector2(160.0, 0.0)
	await run.call(3)
	var at_dry: float = await drink.call(dry)
	place.position = _position_of(pond) + Vector2(160.0, 0.0)
	await run.call(3)
	var at_pond: float = await drink.call(pond)
	_check("a drink is refused on land (%.1f)" % on_land, is_zero_approx(on_land))
	_check("and at cover that isn't drinkable (%.1f)" % at_dry, is_zero_approx(at_dry))
	_check("and restores hydration at water in reach, with no brain (%.1f)" % at_pond, at_pond > 5.0)

	for id in [rabbit, pond, dry]:
		_world.add(id, EcsDyingFlag.new())
	await run.call(1)

## On the ladder: a thirsty rabbit seeks water and drinks until full, with the
## flag up exactly while it drinks; the more urgent of thirst and hunger goes
## first; and being parched wakes a sleeper and keeps it up.
func _a_thirsty_animal_drinks_and_thirst_is_weighed_against_hunger() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsDrinkSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(9000.0, 30000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot)
	var rabbit := _ladder_rabbit(spot + Vector2(350.0, 0.0))
	var thirst := _world.get_component(rabbit, EcsThirstComponent) as EcsThirstComponent
	var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	thirst.hydration = 30.0
	var sought := false
	var drank := false
	var flag_matches := true
	for i in 600:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		sought = sought or brain.state == EcsLowBrainComponent.State.SEEK_WATER
		drank = drank or brain.state == EcsLowBrainComponent.State.DRINK
		flag_matches = flag_matches and _world.has(rabbit, EcsDrinkIntentFlag) \
			== (brain.state == EcsLowBrainComponent.State.DRINK)
		if thirst.hydration >= thirst.max_hydration:
			break
	_check("a thirsty animal seeks water", sought)
	_check("and drinks until full (%.0f)" % thirst.hydration,
		drank and thirst.hydration >= thirst.max_hydration)
	_check("the drink flag is raised exactly while it drinks", flag_matches)

	var berry := _manager.spawn(_world, _catalog, &"berry", _position_of(rabbit))
	var hunger := _world.get_component(rabbit, EcsHungerComponent) as EcsHungerComponent
	var first := func(fullness: float, hydration: float) -> int:
		hunger.fullness = fullness
		thirst.hydration = hydration
		_set_brain_idle(rabbit)
		for i in 1:
			living.run_all(_world, TICK)
			await get_tree().physics_frame
		return brain.state
	var thirstier: int = await first.call(50.0, 20.0)
	var hungrier: int = await first.call(10.0, 50.0)
	_check("thirstier than hungry, it drinks first",
		thirstier == EcsLowBrainComponent.State.DRINK)
	_check("hungrier than thirsty, it eats first", hungrier == EcsLowBrainComponent.State.EAT)

	var tired := _ladder_rabbit(spot + Vector2(0.0, 1500.0))
	var energy := _world.get_component(tired, EcsEnergyComponent) as EcsEnergyComponent
	energy.value = 5.0
	var mind := _world.get_component(tired, EcsLowBrainComponent) as EcsLowBrainComponent
	for i in 6:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	var slept := mind.state == EcsLowBrainComponent.State.SLEEP
	(_world.get_component(tired, EcsThirstComponent) as EcsThirstComponent).hydration = 5.0
	var stayed_up := true
	for i in 6:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		stayed_up = stayed_up and mind.state != EcsLowBrainComponent.State.SLEEP
	_check("being parched wakes a sleeper and keeps it up", slept and stayed_up)

	for id in [rabbit, tired, pond, berry]:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	EcsConst.world_bounds = bounds

## The planner: thirsty prey plan to walk to water and drink, or nothing with no
## water in sight; and utility weighs drink against eat by urgency.
func _thirst_is_planned_and_weighed() -> void:
	var rabbit := _actions([&"eat_ground", &"seek_food", &"seek_bush", &"harvest", &"sleep",
		&"flee", &"go_to_water", &"drink"])
	var hydrated := {&"hydrated": true}
	_check("water in sight: walk to it and drink",
		EcsPlanner.plan({&"water_in_sight": true}, hydrated, rabbit) == [&"go_to_water", &"drink"])
	_check("no water in sight: no plan", EcsPlanner.plan({}, hydrated, rabbit).is_empty())
	_check("parched, it won't plan to sleep",
		EcsPlanner.plan({&"parched": true}, {&"rested": true}, rabbit).is_empty())

	var eat := load("res://9. EcsSystem/defs/goals/satisfy_hunger.tres") as EcsGoalDef
	var quench := load("res://9. EcsSystem/defs/goals/quench.tres") as EcsGoalDef
	var hunger := EcsHungerComponent.new()
	var thirst := EcsThirstComponent.new()
	hunger.fullness = 50.0
	thirst.hydration = 20.0
	_check("thirstier, drink scores higher",
		EcsPlanningSystem.score(quench, hunger, null, null, null, thirst)
			> EcsPlanningSystem.score(eat, hunger, null, null, null, thirst))
	hunger.fullness = 10.0
	thirst.hydration = 50.0
	_check("hungrier, eat scores higher",
		EcsPlanningSystem.score(eat, hunger, null, null, null, thirst)
			> EcsPlanningSystem.score(quench, hunger, null, null, null, thirst))

## A thirsty, planned rabbit walks to a pond where a crocodile lies hidden; the
## crocodile pounces and bites. A kill is many attacks, left to combat planning.
func _thirsty_prey_walk_into_an_ambush() -> void:
	var living := _ambush_pipeline()
	living.add(EcsDrinkSystem.new()).add(EcsDangerSystem.new())
	var spot := Vector2(-9000.0, 30000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot)
	var croc := _ambusher(spot + Vector2(320.0, 0.0))
	var brain := _world.get_component(croc, EcsLowBrainComponent) as EcsLowBrainComponent
	for i in 300:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.AMBUSH and _world.has(croc, EcsHiddenFlag):
			break
	var hidden := _world.has(croc, EcsHiddenFlag)

	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(400.0, 60.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	(_world.get_component(rabbit, EcsThirstComponent) as EcsThirstComponent).hydration = 30.0
	var mind := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var health := _world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent
	var whole := health.value
	var went := false
	var dashed := false
	for i in 900:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if _world.is_alive(rabbit):
			went = went or mind.state == EcsLowBrainComponent.State.SEEK_WATER \
				or mind.state == EcsLowBrainComponent.State.DRINK
		dashed = dashed or _world.has(croc, EcsDashingFlag)
		if dashed and (not _world.is_alive(rabbit) or health.value < whole):
			break
	_check("a hidden crocodile waits at the pond", hidden)
	_check("a thirsty rabbit goes to drink there", went)
	_check("and the crocodile pounces and bites it", dashed
		and (not _world.is_alive(rabbit) or health.value < whole))

	for id in [croc, pond, rabbit]:
		if _world.is_alive(id):
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	var leftover := _first_of(&"corpse")
	while leftover != EcsWorld.NO_ENTITY:
		_world.add(leftover, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		leftover = _first_of(&"corpse")
	EcsConst.world_bounds = bounds

## A fed, rested rabbit on the ladder: no planner, energy set by hand.
func _ladder_rabbit(at: Vector2) -> int:
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", at)
	_world.remove(rabbit, EcsPlannerComponent)
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	return rabbit

## Drops whatever `id`'s brain is doing, as if it had just woken. Test-only.
func _set_brain_idle(id: int) -> void:
	var brain := _world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
	var flag: Script = EcsLowBrainSystem._flag_for(brain.state)
	if flag != null:
		_world.remove(id, flag)
	brain.state = EcsLowBrainComponent.State.IDLE
	brain.target = EcsWorld.NO_ENTITY
	var move := _world.get_component(id, EcsMovementComponent) as EcsMovementComponent
	move.has_destination = false

## Every animal fills the default skills on first sight; a kind's swaps replace
## defaults with the same id. The crocodile dashes harder and hides only in water,
## the dog hides only in bushes.
func _skills_come_from_one_default_set() -> void:
	var resolving := EcsScheduler.new()
	resolving \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSkillSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-40000.0, 0.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot + Vector2(800.0, 0.0))
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot + Vector2(1600.0, 0.0))
	resolving.run_all(_world, TICK)
	await get_tree().physics_frame
	var ids := func(id: int) -> Array:
		return (_world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent).skills.map(
			func(skill: EcsSkillDef) -> StringName: return skill.id)
	var skill := func(id: int, skill_id: StringName) -> EcsSkillDef:
		return EcsSkillDef.find((_world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent).skills, skill_id)
	_check("every animal gets dash, hide and scan",
		ids.call(rabbit) == [&"dash", &"hide", &"scan"] and ids.call(croc) == ids.call(rabbit)
		and ids.call(dog) == ids.call(rabbit))
	_check("the crocodile's swaps replace dash and hide",
		is_equal_approx((skill.call(croc, &"dash") as EcsDashSkill).speed_scale, 3.5)
		and (skill.call(croc, &"hide") as EcsHideSkill).kinds == [&"water"])
	_check("the dog keeps the defaults: a bush hider",
		is_equal_approx((skill.call(dog, &"dash") as EcsDashSkill).speed_scale, 2.0)
		and (skill.call(dog, &"hide") as EcsHideSkill).kinds == [&"bush"])
	for id in [rabbit, croc, dog]:
		_world.add(id, EcsDyingFlag.new())
	resolving.run_all(_world, TICK)
	await get_tree().physics_frame

## From real snapshots: a chase is priced from the two speeds, so the crocodile
## can't chase a rabbit and the dog can. With a lure and prey in sight the same
## actions make the crocodile ambush and the dog chase; with only a bush in sight
## the dog ambushes there; a crocodile sees no lure in a bush.
func _what_a_hunter_does_comes_from_its_stats() -> void:
	var planning := EcsPlanningSystem.new()
	var skills := EcsSkillSystem.new()
	var spot := Vector2(-40000.0, 9000.0)
	var plan_of := func(kind: StringName, offset: Vector2, seen: Array) -> Array[StringName]:
		var hunter := _manager.spawn(_world, _catalog, kind, spot + offset)
		var hunger := _world.get_component(hunter, EcsHungerComponent) as EcsHungerComponent
		hunger.fullness = hunger.forage_below * 0.5
		var energy := _world.get_component(hunter, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true
		energy.value = energy.max_energy
		var sensor := _world.get_component(hunter, EcsSensorComponent) as EcsSensorComponent
		for other in seen:
			sensor.perceived.append(other)
		skills.run(_world, TICK)
		planning.run(_world, TICK)
		var steps := (_world.get_component(hunter, EcsPlannerComponent) as EcsPlannerComponent).steps
		_world.add(hunter, EcsDyingFlag.new())
		return steps
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(300.0, 0.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(0.0, 300.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot + Vector2(0.0, -300.0))
	var croc_chase: Array[StringName] = await plan_of.call(&"crocodile", Vector2.ZERO, [rabbit])
	var dog_chase: Array[StringName] = await plan_of.call(&"wild_dog", Vector2.ZERO, [rabbit])
	var croc_both: Array[StringName] = await plan_of.call(&"crocodile", Vector2.ZERO, [rabbit, pond])
	var dog_bush: Array[StringName] = await plan_of.call(&"wild_dog", Vector2.ZERO, [bush])
	var croc_bush: Array[StringName] = await plan_of.call(&"crocodile", Vector2.ZERO, [bush])
	_check("too slow, the crocodile won't chase a rabbit (%s)" % " > ".join(croc_chase),
		not croc_chase.has(&"hunt"))
	_check("the faster dog will (%s)" % " > ".join(dog_chase),
		not dog_chase.is_empty() and dog_chase[0] == &"hunt")
	_check("a pond and a rabbit in sight: the crocodile ambushes (%s)" % " > ".join(croc_both),
		not croc_both.is_empty() and croc_both[0] == &"go_to_lure")
	_check("only a bush in sight: the dog ambushes there (%s)" % " > ".join(dog_bush),
		not dog_bush.is_empty() and dog_bush[0] == &"go_to_lure" and dog_bush.has(&"ambush"))
	_check("a bush is no lure to a crocodile", not croc_bush.has(&"ambush"))
	for id in [rabbit, pond, bush]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	await get_tree().physics_frame

## Hide holds only in cover of the hider's kind: the dog in a bush, not water; the
## crocodile in water, not a bush.
func _each_kind_hides_in_its_own_cover() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsSkillSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-40000.0, 18000.0)
	var hides_at := func(kind: StringName, cover: StringName, gap: float) -> bool:
		var place := _manager.spawn(_world, _catalog, cover, spot)
		var hider := _manager.spawn(_world, _catalog, kind, spot + Vector2(gap, 0.0))
		_world.remove(hider, EcsLowBrainComponent)
		_cast(hider, &"hide")
		for i in 4:
			living.run_all(_world, TICK)
			await get_tree().physics_frame
		var hidden := _world.has(hider, EcsHiddenFlag)
		for id in [hider, place]:
			_world.add(id, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		return hidden
	var dog_bush: bool = await hides_at.call(&"wild_dog", &"berry_bush", 80.0)
	var dog_water: bool = await hides_at.call(&"wild_dog", &"water", 150.0)
	var croc_water: bool = await hides_at.call(&"crocodile", &"water", 150.0)
	var croc_bush: bool = await hides_at.call(&"crocodile", &"berry_bush", 90.0)
	_check("the dog hides in a bush", dog_bush)
	_check("and not in water", not dog_water)
	_check("the crocodile hides in water", croc_water)
	_check("and not in a bush", not croc_bush)

## A hunter passes over prey it doesn't notice: it won't start a chase on a hidden
## rabbit, and it drops one when the rabbit hides.
func _hidden_prey_is_passed_over() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-40000.0, 27000.0)
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var hunger := _world.get_component(dog, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = 30.0
	var energy := _world.get_component(dog, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(350.0, 0.0))
	_world.remove(rabbit, EcsLowBrainComponent)
	var hidden := EcsHiddenFlag.new()
	hidden.stealth = 0.9
	_world.add(rabbit, hidden)
	var brain := _world.get_component(dog, EcsLowBrainComponent) as EcsLowBrainComponent
	var chased := false
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		chased = chased or brain.state == EcsLowBrainComponent.State.HUNT
	_check("a hunter won't chase prey hidden from it", not chased)
	_world.remove(rabbit, EcsHiddenFlag)
	for i in 60:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		if brain.state == EcsLowBrainComponent.State.HUNT:
			break
	var hunting := brain.state == EcsLowBrainComponent.State.HUNT
	var hide := EcsHiddenFlag.new()
	hide.stealth = 0.9
	_world.add(rabbit, hide)
	for i in 6:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
	_check("it drops a chase when the prey hides",
		hunting and brain.state != EcsLowBrainComponent.State.HUNT
		and brain.state != EcsLowBrainComponent.State.ATTACK)
	for id in [dog, rabbit]:
		_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame

## Staying safe, by cost: beside a bush a frightened rabbit hides in it; in the open
## with its dash ready it escapes, dashing once; with the dash cooling it flees.
func _prey_stay_safe_by_hiding_or_escaping() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-40000.0, 36000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var scared := func(at: Vector2, cooling: bool) -> Dictionary:
		var rabbit := _manager.spawn(_world, _catalog, &"rabbit", at)
		var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true
		energy.value = energy.max_energy
		var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
		danger.value = 0.9
		danger.threat_at = at + Vector2(-200.0, 0.0)
		var known := _world.get_component(rabbit, EcsSkillsComponent) as EcsSkillsComponent
		var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
		var seen := {"hid": false, "escaped": false, "fled": false, "dashes": 0}
		var dashing := false
		for i in 90:
			if cooling and known.resolved:
				known.cooldown_left[&"dash"] = 30.0
			living.run_all(_world, TICK)
			await get_tree().physics_frame
			danger.value = 0.9
			seen["hid"] = seen["hid"] or (brain.state == EcsLowBrainComponent.State.AMBUSH
				and _world.has(rabbit, EcsHiddenFlag))
			seen["escaped"] = seen["escaped"] or brain.state == EcsLowBrainComponent.State.ESCAPE
			seen["fled"] = seen["fled"] or brain.state == EcsLowBrainComponent.State.FLEE
			var now := _world.has(rabbit, EcsDashingFlag)
			if now and not dashing:
				seen["dashes"] += 1
			dashing = now
		_world.add(rabbit, EcsDyingFlag.new())
		return seen
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot)
	var by_bush: Dictionary = await scared.call(spot + Vector2(60.0, 0.0), false)
	var in_open: Dictionary = await scared.call(spot + Vector2(0.0, 2000.0), false)
	var cooling: Dictionary = await scared.call(spot + Vector2(0.0, -2000.0), true)
	_check("beside a bush it hides (%s)" % by_bush, by_bush["hid"])
	_check("in the open with dash ready it escapes, dashing once (%s)" % in_open,
		in_open["escaped"] and in_open["dashes"] == 1)
	_check("with the dash cooling it flees (%s)" % cooling,
		cooling["fled"] and not cooling["escaped"] and cooling["dashes"] == 0)
	_world.add(bush, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	EcsConst.world_bounds = bounds

## A thirsty rabbit at water scans before it drinks; scanning beside a hidden
## crocodile, it sees it and runs instead of drinking.
func _prey_scan_before_drinking() -> void:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsDangerSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsDrinkSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsNodeSyncSystem.new(_manager))
	var spot := Vector2(-40000.0, 45000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var visit := func(at: Vector2, with_croc: bool) -> Dictionary:
		var pond := _manager.spawn(_world, _catalog, &"water", at)
		var croc := EcsWorld.NO_ENTITY
		if with_croc:
			croc = _manager.spawn(_world, _catalog, &"crocodile", at + Vector2(185.0, 40.0))
			_world.remove(croc, EcsLowBrainComponent)
			var hidden := EcsHiddenFlag.new()
			hidden.stealth = 0.95
			_world.add(croc, hidden)
		var rabbit := _manager.spawn(_world, _catalog, &"rabbit", at + Vector2(170.0, 0.0))
		var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true
		energy.value = energy.max_energy
		(_world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent).awareness = 0.0
		var thirst := _world.get_component(rabbit, EcsThirstComponent) as EcsThirstComponent
		# Mildly thirsty, so a seen threat outranks the drink.
		thirst.hydration = 60.0
		var brain := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
		var seen := {"scanned_first": false, "drank": false, "ran": false}
		var scanned := false
		for i in 240:
			living.run_all(_world, TICK)
			await get_tree().physics_frame
			scanned = scanned or _world.has(rabbit, EcsScanningFlag)
			if brain.state == EcsLowBrainComponent.State.DRINK and not seen["drank"]:
				seen["drank"] = true
				seen["scanned_first"] = scanned
			seen["ran"] = seen["ran"] or brain.state == EcsLowBrainComponent.State.FLEE \
				or brain.state == EcsLowBrainComponent.State.ESCAPE
		for id in [pond, croc, rabbit]:
			if id != EcsWorld.NO_ENTITY and _world.is_alive(id):
				_world.add(id, EcsDyingFlag.new())
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		return seen
	var safe: Dictionary = await visit.call(spot, false)
	var watched: Dictionary = await visit.call(spot + Vector2(0.0, 2000.0), true)
	_check("at water it scans, then drinks (%s)" % safe, safe["drank"] and safe["scanned_first"])
	_check("scanning beside a hidden crocodile, it runs (%s)" % watched,
		watched["ran"] and not watched["drank"])
	EcsConst.world_bounds = bounds

## Memory keeps water for drinkers and lures for the hunter that hides in them. A
## fact fades while unseen, a spot seen without its thing is forgotten at once, and
## past capacity the weakest goes.
func _memory_learns_fades_and_is_proven_wrong() -> void:
	var memory := EcsMemorySystem.new()
	var skills := EcsSkillSystem.new()
	var spot := Vector2(-40000.0, 12000.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot)
	var pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(0.0, 200.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot + Vector2(0.0, -200.0))
	var far_bush := _manager.spawn(_world, _catalog, &"berry_bush", spot + Vector2(0.0, -3000.0))
	var sees := func(id: int, seen: Array) -> void:
		var sensor := _world.get_component(id, EcsSensorComponent) as EcsSensorComponent
		sensor.perceived.clear()
		for other in seen:
			sensor.perceived.append(other)
	var facts_of := func(id: int) -> Dictionary:
		return (_world.get_component(id, EcsMemoryComponent) as EcsMemoryComponent).facts
	for id in [rabbit, dog, croc]:
		sees.call(id, [pond, bush])
	sees.call(dog, [pond, bush, far_bush])
	skills.run(_world, TICK)
	memory.run(_world, TICK)
	var r: Dictionary = facts_of.call(rabbit)
	var d: Dictionary = facts_of.call(dog)
	var c: Dictionary = facts_of.call(croc)
	_check("a rabbit remembers a pond as water, and no bush",
		r.size() == 1 and r.has(pond) and r[pond].is_a(EcsMemoryFact.WATER) and not r[pond].is_a(EcsMemoryFact.LURE))
	_check("the dog remembers a bush as a lure, and the pond only as water",
		d.has(bush) and d[bush].is_a(EcsMemoryFact.LURE) and d.has(pond) and not d[pond].is_a(EcsMemoryFact.LURE))
	_check("the crocodile remembers the pond as a lure, and no bush",
		c.has(pond) and c[pond].is_a(EcsMemoryFact.LURE) and c[pond].is_a(EcsMemoryFact.WATER) and not c.has(bush))
	_check("a fact holds where the thing was seen",
		(r[pond] as EcsMemoryFact).position == _position_of(pond))

	var rabbit_at := _world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent
	var remember_for := (_world.get_component(rabbit, EcsMemoryComponent) as EcsMemoryComponent).remember_for
	rabbit_at.position = spot + Vector2(5000.0, 0.0)
	sees.call(rabbit, [])
	memory.run(_world, remember_for * 0.5)
	_check("out of sight, a fact fades but stays",
		r.has(pond) and is_equal_approx((r[pond] as EcsMemoryFact).strength, 0.5))
	sees.call(rabbit, [pond])
	memory.run(_world, TICK)
	_check("seen again, it is fresh", is_equal_approx((r[pond] as EcsMemoryFact).strength, 1.0))
	sees.call(rabbit, [])
	memory.run(_world, remember_for * 1.01)
	_check("unseen for remember_for, it is forgotten", not r.has(pond))

	sees.call(rabbit, [pond])
	memory.run(_world, TICK)
	rabbit_at.position = spot
	sees.call(rabbit, [])
	memory.run(_world, TICK)
	_check("its spot in sight without it, it is forgotten at once", not r.has(pond))

	(d[far_bush] as EcsMemoryFact).strength = 0.5
	(_world.get_component(dog, EcsMemoryComponent) as EcsMemoryComponent).capacity = 2
	sees.call(dog, [pond, bush])
	memory.run(_world, TICK)
	_check("past capacity, the weakest is forgotten (%d kept)" % d.size(),
		d.size() == 2 and not d.has(far_bush))
	for id in [rabbit, dog, croc, pond, bush, far_bush]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	await get_tree().physics_frame

## With no water in sight, a thirsty rabbit plans a walk to a pond it remembers and
## walks to where it saw it; with the pond gone, the arrival forgets it before the
## replan. A dog with no prey or lure in sight walks to a bush it remembers to wait.
func _a_remembered_place_is_planned_and_walked_to() -> void:
	var memory := EcsMemorySystem.new()
	var skills := EcsSkillSystem.new()
	var planning := EcsPlanningSystem.new()
	var brain := EcsLowBrainSystem.new()
	var spot := Vector2(-40000.0, 15000.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var forgetful := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(0.0, 1500.0))
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot + Vector2(0.0, -1500.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(2000.0, 0.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot + Vector2(2000.0, -1500.0))
	for id in [rabbit, forgetful, dog]:
		var energy := _world.get_component(id, EcsEnergyComponent) as EcsEnergyComponent
		energy.rolled = true
		energy.value = energy.max_energy
	for id in [rabbit, forgetful]:
		var thirst := _world.get_component(id, EcsThirstComponent) as EcsThirstComponent
		thirst.hydration = thirst.seek_water_below * 0.5
	var hunger := _world.get_component(dog, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.forage_below * 0.5
	var sensor := _world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent
	sensor.perceived.append(pond)
	(_world.get_component(dog, EcsSensorComponent) as EcsSensorComponent).perceived.append(bush)
	skills.run(_world, TICK)
	memory.run(_world, TICK)
	sensor.perceived.clear()
	(_world.get_component(dog, EcsSensorComponent) as EcsSensorComponent).perceived.clear()
	memory.run(_world, TICK)
	planning.run(_world, TICK)
	var planner := _world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent
	var other := _world.get_component(forgetful, EcsPlannerComponent) as EcsPlannerComponent
	var hunter := _world.get_component(dog, EcsPlannerComponent) as EcsPlannerComponent
	_check("no water in sight, it walks to a pond it remembers (%s)" % " > ".join(planner.steps),
		planner.steps == [&"recall_water", &"drink"])
	_check("remembering none, it has no way to quench (%s)" % other.goal, other.goal != &"quench")
	_check("a dog with no prey or lure in sight walks to a bush it remembers (%s)" % " > ".join(hunter.steps),
		not hunter.steps.is_empty() and hunter.steps[0] == &"recall_lure" and hunter.steps.has(&"ambush"))

	brain.run(_world, TICK)
	var mind := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var move := _world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent
	var fact := (_world.get_component(rabbit, EcsMemoryComponent) as EcsMemoryComponent).facts[pond] as EcsMemoryFact
	_check("it walks to where it saw the pond",
		mind.state == EcsLowBrainComponent.State.RECALL and mind.target == pond
		and move.has_destination and move.destination == fact.position)
	var reach := _world.get_component(rabbit, EcsActionComponent) as EcsActionComponent
	reach.reached.append(pond)
	brain.run(_world, TICK)
	_check("in reach of it, the walk stops (%s)" % EcsLowBrainComponent.STATE_NAMES[mind.state],
		mind.state != EcsLowBrainComponent.State.RECALL and not move.has_destination)
	reach.reached.clear()

	_world.add(pond, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	(_world.get_component(rabbit, EcsPositionComponent) as EcsPositionComponent).position = fact.position
	memory.run(_world, TICK)
	planning.run(_world, TICK)
	_check("arriving to find it gone, it forgets it before the replan (%s)" % " > ".join(planner.steps),
		not (_world.get_component(rabbit, EcsMemoryComponent) as EcsMemoryComponent).facts.has(pond)
		and not planner.steps.has(&"recall_water"))
	for id in [rabbit, forgetful, dog, bush]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	await get_tree().physics_frame

## A pond where a threat was met is feared and priced dearer, so a farther safe one wins
## until the fear fades; a feared pond still beats none. A lure where prey was seen gains
## traffic and wins though farther; a corpse there counts once; traffic halves.
func _fear_and_traffic_price_places() -> void:
	var memory := EcsMemorySystem.new()
	var skills := EcsSkillSystem.new()
	var planning := EcsPlanningSystem.new()
	var brain := EcsLowBrainSystem.new()
	var spot := Vector2(-40000.0, 18000.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var near_pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(300.0, 0.0))
	var far_pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(-900.0, 0.0))
	var energy := _world.get_component(rabbit, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	var thirst := _world.get_component(rabbit, EcsThirstComponent) as EcsThirstComponent
	thirst.hydration = thirst.seek_water_below * 0.5
	var sensor := _world.get_component(rabbit, EcsSensorComponent) as EcsSensorComponent
	sensor.perceived.append_array([near_pond, far_pond])
	var mind := _world.get_component(rabbit, EcsMemoryComponent) as EcsMemoryComponent
	var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
	var speed := (_world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent).speed
	memory.run(_world, TICK)
	danger.value = danger.flee_at * 0.5
	danger.threat_at = _position_of(far_pond)
	memory.run(_world, TICK)
	_check("a threat below fleeing frightens no pond",
		(mind.facts[far_pond] as EcsMemoryFact).fear == 0.0)
	danger.value = danger.flee_at + 0.1
	danger.threat_at = _position_of(near_pond)
	memory.run(_world, TICK)
	danger.value = 0.0
	_check("a threat met by a pond makes it feared, and not a far one",
		(mind.facts[near_pond] as EcsMemoryFact).fear > 0.99
		and (mind.facts[far_pond] as EcsMemoryFact).fear == 0.0)
	planning.run(_world, TICK)
	brain.run(_world, TICK)
	var state := _world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent
	var planner := _world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent
	_check("the nearer pond feared, it goes to the far one (%s)" % " > ".join(planner.steps),
		planner.steps == [&"go_to_water", &"drink"] and state.target == far_pond)
	memory.run(_world, mind.fear_for)
	var here := _position_of(rabbit)
	_check("once the fear fades, the near one is cheaper again",
		EcsMemoryFact.best(mind, here, speed, EcsMemoryFact.WATER, true, sensor.perceived).about == near_pond)
	(mind.facts[near_pond] as EcsMemoryFact).fear = 1.0
	mind.facts.erase(far_pond)
	_check("a feared pond still beats none",
		EcsMemoryFact.best(mind, here, speed, EcsMemoryFact.WATER, true, sensor.perceived).about == near_pond)

	var spot2 := spot + Vector2(0.0, 3000.0)
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot2)
	var near_bush := _manager.spawn(_world, _catalog, &"berry_bush", spot2 + Vector2(300.0, 0.0))
	var busy_bush := _manager.spawn(_world, _catalog, &"berry_bush", spot2 + Vector2(-700.0, 0.0))
	var visitor := _manager.spawn(_world, _catalog, &"rabbit", spot2 + Vector2(-700.0, 120.0))
	var dog_energy := _world.get_component(dog, EcsEnergyComponent) as EcsEnergyComponent
	dog_energy.rolled = true
	dog_energy.value = dog_energy.max_energy
	var hunger := _world.get_component(dog, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.forage_below * 0.5
	var eyes := _world.get_component(dog, EcsSensorComponent) as EcsSensorComponent
	eyes.perceived.append_array([near_bush, busy_bush, visitor])
	var dog_mind := _world.get_component(dog, EcsMemoryComponent) as EcsMemoryComponent
	var dog_speed := (_world.get_component(dog, EcsMovementComponent) as EcsMovementComponent).speed
	skills.run(_world, TICK)
	memory.run(_world, TICK)
	memory.run(_world, 5.0)
	var busy := dog_mind.facts[busy_bush] as EcsMemoryFact
	var quiet := dog_mind.facts[near_bush] as EcsMemoryFact
	_check("prey seen by a lure builds its traffic, not another's (%.1f, %.1f)" % [busy.traffic, quiet.traffic],
		busy.traffic > 4.0 and quiet.traffic == 0.0)
	eyes.perceived.erase(visitor)
	planning.run(_world, TICK)
	brain.run(_world, TICK)
	var dog_state := _world.get_component(dog, EcsLowBrainComponent) as EcsLowBrainComponent
	var dog_plan := _world.get_component(dog, EcsPlannerComponent) as EcsPlannerComponent
	_check("the dog goes to the busier lure though it is farther (%s)" % " > ".join(dog_plan.steps),
		not dog_plan.steps.is_empty() and dog_plan.steps[0] == &"go_to_lure" and dog_state.target == busy_bush)

	var corpse := _manager.spawn(_world, _catalog, &"corpse", spot2 + Vector2(300.0, 100.0))
	eyes.perceived.append(corpse)
	memory.run(_world, TICK)
	memory.run(_world, TICK)
	_check("a corpse by a lure counts once (%.2f)" % quiet.traffic,
		quiet.traffic > dog_mind.kill_traffic * 0.99 and quiet.traffic <= dog_mind.kill_traffic)
	eyes.perceived.erase(corpse)
	var before := busy.traffic
	memory.run(_world, dog_mind.traffic_half_life)
	_check("traffic halves over its half-life", is_equal_approx(busy.traffic, before * 0.5))
	for id in [rabbit, near_pond, far_pond, dog, near_bush, busy_bush, visitor, corpse]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	await get_tree().physics_frame

## Each animal remembers what matters to it, by its own needs and power: a monkey keeps
## ponds, stocked bushes and the threat its danger found, and no rabbit; a dog keeps prey,
## the crocodile as a threat and bushes as lures. An emptied bush is forgotten; a remembered
## bush is walked to when hungry; a remembered threat makes the pond beside it dearer.
func _memory_keeps_what_matters_to_it() -> void:
	var memory := EcsMemorySystem.new()
	var skills := EcsSkillSystem.new()
	var planning := EcsPlanningSystem.new()
	var spot := Vector2(-40000.0, 24000.0)
	var monkey := _manager.spawn(_world, _catalog, &"monkey", spot)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(0.0, -150.0))
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot + Vector2(0.0, 250.0))
	var pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(250.0, 0.0))
	var croc := _manager.spawn(_world, _catalog, &"crocodile", spot + Vector2(200.0, 0.0))
	var far_pond := _manager.spawn(_world, _catalog, &"water", spot + Vector2(-700.0, 0.0))
	var bush := _manager.spawn(_world, _catalog, &"berry_bush", spot + Vector2(-200.0, -200.0))
	var crop := _world.get_component(bush, EcsHarvestableComponent) as EcsHarvestableComponent
	crop.stocked = true
	crop.stock = crop.stock_max
	var sees := func(id: int, seen: Array) -> void:
		var sensor := _world.get_component(id, EcsSensorComponent) as EcsSensorComponent
		sensor.perceived.clear()
		for other in seen:
			sensor.perceived.append(other)
	sees.call(monkey, [rabbit, dog, croc, bush, pond, far_pond])
	sees.call(dog, [rabbit, monkey, croc, bush])
	skills.run(_world, TICK)
	EcsDangerSystem.new().run(_world, TICK)
	memory.run(_world, TICK)
	var m := (_world.get_component(monkey, EcsMemoryComponent) as EcsMemoryComponent).facts
	var d := (_world.get_component(dog, EcsMemoryComponent) as EcsMemoryComponent).facts
	var is_a := func(facts: Dictionary, id: int, kind: int) -> bool:
		return facts.has(id) and (facts[id] as EcsMemoryFact).is_a(kind)
	_check("a monkey keeps the pond, the stocked bush and the crocodile as a threat",
		is_a.call(m, pond, EcsMemoryFact.WATER) and is_a.call(m, bush, EcsMemoryFact.BUSH)
		and is_a.call(m, croc, EcsMemoryFact.THREAT))
	_check("and no rabbit, which is nothing to it", not m.has(rabbit))
	_check("a dog keeps rabbit and monkey as prey, the crocodile as a threat, the bush as a lure",
		is_a.call(d, rabbit, EcsMemoryFact.PREY) and is_a.call(d, monkey, EcsMemoryFact.PREY)
		and is_a.call(d, croc, EcsMemoryFact.THREAT) and is_a.call(d, bush, EcsMemoryFact.LURE)
		and not is_a.call(d, bush, EcsMemoryFact.BUSH))

	var mind := _world.get_component(monkey, EcsMemoryComponent) as EcsMemoryComponent
	var speed := (_world.get_component(monkey, EcsMovementComponent) as EcsMovementComponent).speed
	var sight := (_world.get_component(monkey, EcsSensorComponent) as EcsSensorComponent).perceived
	_check("a pond beside a remembered crocodile is dearer than a far one",
		EcsMemoryFact.best(mind, spot, speed, EcsMemoryFact.WATER, true, sight).about == far_pond)

	crop.stock = 0
	memory.run(_world, TICK)
	_check("a bush seen emptied is forgotten", not m.has(bush))

	crop.stock = crop.stock_max
	memory.run(_world, TICK)
	var energy := _world.get_component(monkey, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	var hunger := _world.get_component(monkey, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.forage_below * 0.5
	(_world.get_component(monkey, EcsPositionComponent) as EcsPositionComponent).position = spot + Vector2(0.0, 5000.0)
	sees.call(monkey, [])
	memory.run(_world, TICK)
	planning.run(_world, TICK)
	var steps := (_world.get_component(monkey, EcsPlannerComponent) as EcsPlannerComponent).steps
	_check("hungry, no bush in sight, it walks to one it remembers (%s)" % " > ".join(steps),
		not steps.is_empty() and steps[0] == &"recall_bush" and steps.has(&"harvest"))
	for id in [monkey, rabbit, dog, pond, croc, far_pond, bush]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)
	await get_tree().physics_frame

## A hit landed while dashing stuns; a plain one doesn't. A stunned animal drops its trip
## and can't attack, and the stun wears off on time.
func _a_stun_holds_still_and_wears_off() -> void:
	var skills := EcsSkillSystem.new()
	var attack := EcsAttackSystem.new()
	var damage := EcsDamageSystem.new()
	var brain := EcsLowBrainSystem.new()
	var spot := Vector2(-40000.0, 27000.0)
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(30.0, 0.0))
	skills.run(_world, TICK)
	var reach := _world.get_component(dog, EcsActionComponent) as EcsActionComponent
	reach.reached.append(rabbit)
	var intent := EcsAttackIntentFlag.new()
	intent.target_id = rabbit
	_world.add(dog, intent)
	attack.run(_world, TICK)
	damage.run(_world, TICK)
	_check("a plain bite doesn't stun", not _world.has(rabbit, EcsStunnedFlag))
	(_world.get_component(dog, EcsDamageComponent) as EcsDamageComponent).cooldown = 0.0
	_world.add(dog, EcsDashingFlag.new())
	attack.run(_world, TICK)
	damage.run(_world, TICK)
	var stun := _world.get_component(rabbit, EcsStunnedFlag) as EcsStunnedFlag
	_check("a bite while dashing stuns for the dash's stun (%.1fs)" % (stun.left if stun else 0.0),
		stun != null and is_equal_approx(stun.left, 1.5))

	var move := _world.get_component(rabbit, EcsMovementComponent) as EcsMovementComponent
	move.destination = spot + Vector2(500.0, 0.0)
	move.has_destination = true
	brain.run(_world, TICK)
	_check("stunned, it drops its trip",
		not move.has_destination and (_world.get_component(rabbit, EcsLowBrainComponent) as EcsLowBrainComponent).state == EcsLowBrainComponent.State.IDLE)
	_world.add(dog, EcsStunnedFlag.new())
	(_world.get_component(dog, EcsStunnedFlag) as EcsStunnedFlag).left = 1.0
	(_world.get_component(dog, EcsDamageComponent) as EcsDamageComponent).cooldown = 0.0
	var before := (_world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent).value
	_world.add(dog, intent)
	attack.run(_world, TICK)
	damage.run(_world, 0.5)
	_check("a stunned attacker doesn't bite",
		(_world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent).value == before)
	damage.run(_world, 1.1)
	_check("the stun wears off on time",
		not _world.has(rabbit, EcsStunnedFlag) and not _world.has(dog, EcsStunnedFlag))
	for id in [dog, rabbit]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)

## A rabbit beside a bush hides from a threat that isn't after it, but not from one
## chasing it: hunted, it runs.
func _hunted_prey_cannot_hide() -> void:
	var planning := EcsPlanningSystem.new()
	var spot := Vector2(-40000.0, 30000.0)
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot)
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot + Vector2(200.0, 0.0))
	var danger := _world.get_component(rabbit, EcsDangerComponent) as EcsDangerComponent
	danger.threat = dog
	danger.value = 1.0
	var hunter := _world.get_component(dog, EcsLowBrainComponent) as EcsLowBrainComponent
	planning.run(_world, TICK)
	var facts := (_world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent).facts
	_check("a threat not after it: not hunted", not facts.has(&"hunted"))
	hunter.state = EcsLowBrainComponent.State.HUNT
	hunter.target = rabbit
	planning.run(_world, TICK)
	facts = (_world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent).facts
	_check("the threat chasing it: hunted", facts.has(&"hunted"))
	var actions := (_world.get_component(rabbit, EcsPlannerComponent) as EcsPlannerComponent).actions
	var calm := EcsPlanner.plan({&"threat_near": true, &"in_cover": true}, {&"safe": true}, actions)
	var chased := EcsPlanner.plan({&"threat_near": true, &"in_cover": true, &"hunted": true},
		{&"safe": true}, actions)
	_check("in cover, a threat not after it: hide (%s)" % " > ".join(calm), calm == [&"hide"])
	_check("in cover but hunted: run, not hide (%s)" % " > ".join(chased),
		not chased.is_empty() and not chased.has(&"hide"))
	hunter.state = EcsLowBrainComponent.State.IDLE
	hunter.target = EcsWorld.NO_ENTITY
	for id in [rabbit, dog]:
		_world.add(id, EcsDyingFlag.new())
	EcsLifecycleSystem.new(_manager, _catalog).run(_world, TICK)

## Live: a hungry dog pounces on a rabbit standing near, the pounce stuns it, and the dog
## keeps biting until it is dead.
func _a_pounce_stuns_and_bites_follow_until_dead() -> void:
	var living := _ambush_pipeline()
	var spot := Vector2(33000.0, -36000.0)
	var bounds := EcsConst.world_bounds
	EcsConst.world_bounds = Rect2(spot - Vector2(3000.0, 3000.0), Vector2(6000.0, 6000.0))
	var dog := _manager.spawn(_world, _catalog, &"wild_dog", spot)
	var energy := _world.get_component(dog, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	var hunger := _world.get_component(dog, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = hunger.forage_below * 0.5
	var rabbit := _manager.spawn(_world, _catalog, &"rabbit", spot + Vector2(130.0, 0.0))
	_world.remove(rabbit, EcsLowBrainComponent)
	var health := _world.get_component(rabbit, EcsHealthComponent) as EcsHealthComponent
	var brain := _world.get_component(dog, EcsLowBrainComponent) as EcsLowBrainComponent
	var pounced := false
	var stunned := false
	var bites := 0
	var last := health.value
	for i in 900:
		living.run_all(_world, TICK)
		await get_tree().physics_frame
		pounced = pounced or brain.state == EcsLowBrainComponent.State.POUNCE
		stunned = stunned or _world.has(rabbit, EcsStunnedFlag)
		if not _world.is_alive(rabbit):
			break
		if health.value < last:
			bites += 1
		last = health.value
	_check("the dog pounces and the pounce stuns", pounced and stunned)
	_check("it keeps biting until the rabbit is dead (%d bites)" % bites,
		not _world.is_alive(rabbit) and bites >= 2)
	_world.add(dog, EcsDyingFlag.new())
	for id in _world.query([EcsNameComponent, EcsPositionComponent], [EcsDyingFlag]):
		if _position_of(id).distance_to(spot) < 2000.0:
			_world.add(id, EcsDyingFlag.new())
	living.run_all(_world, TICK)
	await get_tree().physics_frame
	EcsConst.world_bounds = bounds

func _ambush_pipeline() -> EcsScheduler:
	var living := EcsScheduler.new()
	living \
		.add(EcsLifecycleSystem.new(_manager, _catalog)) \
		.add(EcsHealthSystem.new()) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsPlanningSystem.new()) \
		.add(EcsLowBrainSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsConsumeSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsCritSystem.new()) \
		.add(EcsDamageSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsCorpseSystem.new()) \
		.add(EcsDropSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager))
	return living

## A hungry, rested crocodile.
func _ambusher(at: Vector2) -> int:
	var croc := _manager.spawn(_world, _catalog, &"crocodile", at)
	var energy := _world.get_component(croc, EcsEnergyComponent) as EcsEnergyComponent
	energy.rolled = true
	energy.value = energy.max_energy
	var hunger := _world.get_component(croc, EcsHungerComponent) as EcsHungerComponent
	hunger.fullness = 100.0
	return croc

## Raises a cast intent, standing in for the brain.
func _cast(id: int, skill: StringName) -> void:
	var cast := EcsCastIntentFlag.new()
	cast.skill = skill
	_world.add(id, cast)

func _actions(ids: Array[StringName]) -> Array[EcsActionDef]:
	var found: Array[EcsActionDef] = []
	for action_id in ids:
		found.append(load("res://9. EcsSystem/defs/actions/%s.tres" % action_id) as EcsActionDef)
	return found

## Live berries within `radius` of `spot`.
func _berries_near(spot: Vector2, radius: float) -> Array[int]:
	var found: Array[int] = []
	for id in _world.query([EcsNameComponent, EcsPositionComponent], [EcsDyingFlag]):
		var named := _world.get_component(id, EcsNameComponent) as EcsNameComponent
		var at := _world.get_component(id, EcsPositionComponent) as EcsPositionComponent
		if named.type_id == &"berry" and at.position.distance_to(spot) <= radius:
			found.append(id)
	return found

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

func _position_of(id: int) -> Vector2:
	return (_world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position

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
