extends Node2D

## Module 11's test: input written straight onto EcsPlayerInputSingleton, run through the real
## pipeline — moving, sprinting, the dash, being stunned, attacks aimed and tapped, the
## cooldown, a dummy broken and back, and skill slots.
##
##   "$GODOT" --headless --path . "res://11. EcsControl/tests/control_test.tscn"
##
## Exits 0 only if every check passes. Each tick awaits a physics frame so reach is real.

const CATALOG := preload("res://11. EcsControl/defs/entity_catalog.tres")
const TICK: float = 1.0 / 60.0

var _checks: int = 0
var _failures: int = 0
var _world: EcsWorld
var _scheduler: EcsScheduler
var _manager: EcsEntityManager
var _input: EcsPlayerInputSingleton
var _root: Node2D
var _player: int = EcsWorld.NO_ENTITY

func _ready() -> void:
	await _moving()
	await _a_dash_and_a_stun()
	await _attacks()
	await _a_dummy_breaks_and_comes_back()
	await _skill_slots()
	print("[control] %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)

func _moving() -> void:
	await _setup([])
	var speed := _movement().speed
	_input.move = Vector2.RIGHT
	var x := await _travel(60)
	_check("a full stick for 1 s covers its speed (%.1f px of %.1f)" % [x, speed], absf(x - speed) < 1.0)
	_input.move = Vector2(0.5, 0.0)
	x = await _travel(60)
	var half := speed * pow(0.5, _player_of().speed_curve)
	_check("half a stick is slower, on the curve (%.1f px of %.1f)" % [x, half], absf(x - half) < 1.0)
	_input.move = Vector2.RIGHT
	_input.sprint = true
	x = await _travel(60)
	_check("sprint is faster (%.1f px of %.1f)" % [x, speed * _player_of().sprint_multiplier],
		absf(x - speed * _player_of().sprint_multiplier) < 1.0)
	_input.sprint = false
	_input.move = Vector2.ZERO
	x = await _travel(10)
	_check("letting go stops it", is_zero_approx(x))
	_check("it faces the way it moved", _player_of().facing == Vector2.RIGHT)

func _a_dash_and_a_stun() -> void:
	await _setup([])
	_input.move = Vector2.RIGHT
	_input.sprint_pressed = true
	await _ticks(1)
	_input.sprint_pressed = false
	await _ticks(3)
	_check("one sprint press is not a dash", not _world.has(_player, EcsDashingFlag))
	_input.sprint_pressed = true
	var from := _place().x
	_scheduler.run_all(_world, TICK)
	_input.sprint_pressed = false
	var dash := _world.get_component(_player, EcsDashingFlag) as EcsDashingFlag
	_check("a double-tap dashes in the same tick", dash != null)
	if dash != null:
		_check("and the dash speeds the steer (%.1f px a tick)" % (_place().x - from),
			is_equal_approx(_place().x - from, _movement().speed * dash.speed_scale * TICK))
	await _ticks(30)
	_check("the dash ends", not _world.has(_player, EcsDashingFlag))
	var stun := EcsStunnedFlag.new()
	stun.left = 5.0
	_world.add(_player, stun)
	_input.actions.append({"ability": EcsPlayerInputSingleton.SKILLS[1], "aim": Vector2.ZERO, "tapped": true})
	var x := await _travel(10)
	_check("stunned, it doesn't move", is_zero_approx(x))
	_check("or cast", not _world.has(_player, EcsCastIntentFlag) and not _world.has(_player, EcsScanningFlag))
	_input.move = Vector2.ZERO

func _attacks() -> void:
	await _setup([Vector2(50, 0), Vector2(0, 200)])
	var near := _dummy_at(Vector2(50, 0))
	var far := _dummy_at(Vector2(0, 200))
	var damage := (_world.get_component(_player, EcsDamageComponent) as EcsDamageComponent).damage
	_press(Vector2.RIGHT)
	_scheduler.run_all(_world, TICK)
	_check("an aimed attack lands in the tick of its input (%.0f)" % _health(near), is_equal_approx(_health(near), 100.0 - damage))
	await get_tree().physics_frame
	await _ticks(1)
	_check("the attack intent is gone the next tick", not _world.has(_player, EcsAttackIntentFlag))
	_press(Vector2.RIGHT)
	await _ticks(1)
	_check("a press while the attack cools does nothing", is_equal_approx(_health(near), 100.0 - damage))
	await _cool()
	_press(Vector2.LEFT)
	await _ticks(1)
	_check("an aim outside the cone hits nothing", is_equal_approx(_health(near), 100.0 - damage))
	await _cool()
	_press(Vector2.DOWN)
	await _ticks(1)
	_check("a dummy out of reach is not hit", is_equal_approx(_health(far), 100.0))
	_check("and the facing follows the aim", _player_of().facing == Vector2.DOWN)

	await _setup([Vector2(60, 0), Vector2(0, -48)])
	var closer := _dummy_at(Vector2(0, -48))
	var other := _dummy_at(Vector2(60, 0))
	_input.actions.append({"ability": EcsPlayerInputSingleton.ATTACK, "aim": Vector2.ZERO, "tapped": true})
	await _ticks(1)
	_check("a tap takes the nearest in reach", _health(closer) < 100.0 and is_equal_approx(_health(other), 100.0))

func _a_dummy_breaks_and_comes_back() -> void:
	await _setup([Vector2(50, 0)])
	var dummy := _dummy_at(Vector2(50, 0))
	for i in 10:
		if not _world.is_alive(dummy) or _world.has(dummy, EcsDyingFlag):
			break
		_press(Vector2.RIGHT)
		await _ticks(1)
		await _cool()
	await _ticks(2)
	_check("hit to 0, the dummy is gone", not _world.is_alive(dummy))
	_check("and a wreck stands where it was", _count(&"dummy_wreck") == 1 and _count(&"dummy") == 0)
	var after := (CATALOG.get_def(&"dummy_wreck").components.filter(
		func(c: EcsComponent) -> bool: return c is EcsRespawnComponent)[0] as EcsRespawnComponent).after
	await _ticks(roundi(after / TICK) + 2)
	_check("after %.0f s the dummy is back and the wreck gone" % after, _count(&"dummy") == 1 and _count(&"dummy_wreck") == 0)
	var back := _dummy_at(Vector2(50, 0))
	_check("where it stood, at full health", back != EcsWorld.NO_ENTITY and is_equal_approx(_health(back), 100.0))

func _skill_slots() -> void:
	await _setup([])
	_input.actions.append({"ability": EcsPlayerInputSingleton.SKILLS[1], "aim": Vector2.ZERO, "tapped": true})
	_scheduler.run_all(_world, TICK)
	_check("skill stick 2 casts its slot's skill (scan) in the same tick", _world.has(_player, EcsScanningFlag))
	await get_tree().physics_frame
	await _ticks(1)
	_check("a timed skill's cast intent lasts one tick", not _world.has(_player, EcsCastIntentFlag))
	_input.actions.append({"ability": EcsPlayerInputSingleton.SKILLS[3], "aim": Vector2.ZERO, "tapped": true})
	await _ticks(1)
	_check("an empty slot casts nothing", not _world.has(_player, EcsCastIntentFlag))
	_input.actions.append({"ability": EcsPlayerInputSingleton.SKILLS[2], "aim": Vector2.ZERO, "tapped": true})
	await _ticks(1)
	_check("hide out of cover is refused by the skill, not the control", not _world.has(_player, EcsHiddenFlag))

## A fresh world with the player at the origin and dummies at `dummies`.
func _setup(dummies: Array) -> void:
	if _root != null:
		_manager.clear()
		_root.free()
	_root = Node2D.new()
	add_child(_root)
	_manager = EcsEntityManager.new(_root)
	_world = EcsWorld.new()
	_input = EcsPlayerInputSingleton.new()
	_world.add_singleton(_input)
	var inbox := EcsLifecycleSingleton.new()
	_world.add_singleton(inbox)
	_world.add_singleton(EcsCombatSingleton.new())
	_world.add_singleton(EcsHealthSingleton.new())
	_ask(inbox, &"player", Vector2.ZERO)
	for at: Vector2 in dummies:
		_ask(inbox, &"dummy", at)
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, CATALOG)) \
		.add(EcsPlayerControlSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsHealthSystem.new()) \
		.add(EcsDangerSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsRemainsSystem.new()) \
		.add(EcsRespawnSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager)) \
		.add(EcsPlayerViewSystem.new(_manager, null, null))
	await _ticks(3)
	_player = _world.query([EcsPlayerComponent])[0]
	(_world.get_component(_player, EcsDamageComponent) as EcsDamageComponent).crit_chance = 0.0

func _ask(inbox: EcsLifecycleSingleton, type_id: StringName, at: Vector2) -> void:
	var note := EcsSpawnRequest.new()
	note.type_id = type_id
	note.position = at
	inbox.spawn_requests.append(note)

func _ticks(count: int) -> void:
	for i in count:
		_scheduler.run_all(_world, TICK)
		await get_tree().physics_frame

## Runs `count` ticks and returns how far the player went in x.
func _travel(count: int) -> float:
	var from := _place().x
	await _ticks(count)
	return _place().x - from

func _cool() -> void:
	var attack := _world.get_component(_player, EcsDamageComponent) as EcsDamageComponent
	await _ticks(ceili(attack.interval / TICK) + 1)

func _press(aim: Vector2) -> void:
	_input.actions.append({"ability": EcsPlayerInputSingleton.ATTACK, "aim": aim, "tapped": false})

func _place() -> Vector2:
	return (_world.get_component(_player, EcsPositionComponent) as EcsPositionComponent).position

func _movement() -> EcsMovementComponent:
	return _world.get_component(_player, EcsMovementComponent) as EcsMovementComponent

func _player_of() -> EcsPlayerComponent:
	return _world.get_component(_player, EcsPlayerComponent) as EcsPlayerComponent

func _health(id: int) -> float:
	var health := _world.get_component(id, EcsHealthComponent) as EcsHealthComponent
	return health.value if health != null else -1.0

func _dummy_at(at: Vector2) -> int:
	for id in _world.query([EcsHealthComponent, EcsPositionComponent], [EcsPlayerComponent]):
		if (_world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position.distance_to(at) < 8.0:
			return id
	return EcsWorld.NO_ENTITY

func _count(type_id: StringName) -> int:
	var n := 0
	for id in _world.query([EcsNameComponent], [EcsDyingFlag]):
		if (_world.get_component(id, EcsNameComponent) as EcsNameComponent).type_id == type_id:
			n += 1
	return n

func _check(what: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("[control] %s  %s" % ["ok  " if passed else "FAIL", what])
