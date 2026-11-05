class_name EcsPlayerControlSystem
extends EcsSystem

## The player's brain. Reads EcsPlayerInputSingleton and writes what a brain would: the
## movement's `steer`, the facing, and the intent flags module 9's executors carry out in this
## same tick. An attack intent lasts one tick; a timed skill's cast too; a held skill's cast
## stays until its stick is used again. Stunned or collapsed, it does nothing.

func label() -> StringName:
	return &"control"

func run(world: EcsWorld, delta: float) -> void:
	var input := world.get_singleton(EcsPlayerInputSingleton) as EcsPlayerInputSingleton
	if input == null:
		return
	for id in world.query([EcsPlayerComponent, EcsAttackIntentFlag]):
		world.remove(id, EcsAttackIntentFlag)
	for id in world.query([EcsPlayerComponent, EcsCastIntentFlag]):
		var cast := world.get_component(id, EcsCastIntentFlag) as EcsCastIntentFlag
		if not _held(world, id, cast.skill):
			world.remove(id, EcsCastIntentFlag)

	for id in world.query([EcsPlayerComponent, EcsMovementComponent], [EcsDyingFlag]):
		var player := world.get_component(id, EcsPlayerComponent) as EcsPlayerComponent
		var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
		player.since_sprint += delta
		if world.has(id, EcsStunnedFlag) or world.has(id, EcsCollapsedFlag):
			move.steer = Vector2.ZERO
			continue
		move.steer = _steer(player, input)
		if input.aim != Vector2.ZERO:
			player.facing = input.aim.normalized()
		elif input.move != Vector2.ZERO:
			player.facing = input.move.normalized()
		if input.sprint_pressed:
			if player.since_sprint <= player.double_tap_window:
				_cast(world, id, player.dash_skill)
				player.since_sprint = 1000.0
			else:
				player.since_sprint = 0.0
		for action in input.actions:
			_act(world, id, player, action)
	input.actions.clear()

## Stick to steer, as module 7 moved: speed by stick distance, or full speed times the
## multiplier while sprinting.
func _steer(player: EcsPlayerComponent, input: EcsPlayerInputSingleton) -> Vector2:
	if input.move == Vector2.ZERO:
		return Vector2.ZERO
	if input.sprint:
		return input.move.normalized() * player.sprint_multiplier
	return input.move.normalized() * pow(minf(input.move.length(), 1.0), player.speed_curve)

func _act(world: EcsWorld, id: int, player: EcsPlayerComponent, action: Dictionary) -> void:
	var aim: Vector2 = action.aim
	if aim != Vector2.ZERO:
		player.facing = aim.normalized()
	var ability: StringName = action.ability
	if ability == EcsPlayerInputSingleton.ATTACK:
		var target := _target(world, id, player, aim, action.tapped or aim == Vector2.ZERO)
		if target != EcsWorld.NO_ENTITY:
			var intent := EcsAttackIntentFlag.new()
			intent.target_id = target
			world.add(id, intent)
		return
	var slot := EcsPlayerInputSingleton.SKILLS.find(ability)
	if slot >= 0 and slot < player.skill_slots.size() and player.skill_slots[slot] != &"":
		_cast(world, id, player.skill_slots[slot])

## The reached entity with health to hit: the nearest inside the aim cone, or the nearest
## at all on a tap.
func _target(world: EcsWorld, id: int, player: EcsPlayerComponent, aim: Vector2, tapped: bool) -> int:
	var reach := world.get_component(id, EcsActionComponent) as EcsActionComponent
	if reach == null:
		return EcsWorld.NO_ENTITY
	var here := (world.get_component(id, EcsPositionComponent) as EcsPositionComponent).position
	var best := EcsWorld.NO_ENTITY
	var nearest := INF
	for other in reach.reached:
		if not world.has(other, EcsHealthComponent) or world.has(other, EcsDyingFlag):
			continue
		var to := (world.get_component(other, EcsPositionComponent) as EcsPositionComponent).position - here
		if not tapped and to != Vector2.ZERO and rad_to_deg(absf(aim.angle_to(to))) > player.aim_cone:
			continue
		if to.length() < nearest:
			nearest = to.length()
			best = other
	return best

## Asks for `skill`; using a held skill that is running asks for it to stop.
func _cast(world: EcsWorld, id: int, skill: StringName) -> void:
	if world.has(id, EcsCastIntentFlag):
		var was := (world.get_component(id, EcsCastIntentFlag) as EcsCastIntentFlag).skill
		world.remove(id, EcsCastIntentFlag)
		if was == skill and _held(world, id, skill):
			return
	var cast := EcsCastIntentFlag.new()
	cast.skill = skill
	world.add(id, cast)

## Whether `skill` is one that lasts while asked for.
func _held(world: EcsWorld, id: int, skill: StringName) -> bool:
	var known := world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent
	var def := EcsSkillDef.find(known.skills, skill) if known != null else null
	return def != null and is_zero_approx(def.duration)
