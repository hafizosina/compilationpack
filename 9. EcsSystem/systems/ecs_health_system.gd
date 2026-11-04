class_name EcsHealthSystem
extends EcsSystem

## The only writer of EcsHealthComponent.value, and where death is decided.
## Applies over-time effects, this run's hits (less armour, raising hurt, stun,
## bleeding and poison) and the health inbox, then flags dying at zero. Visits
## only entities with something pending, so idle health costs nothing.
## Also counts stuns down, since only a hit raises one.

## Every over-time effect it applies; a new one is a flag and a line here.
var kinds: Array[Script] = [
	EcsStarvingFlag, EcsDehydratingFlag, EcsMendingFlag, EcsBleedingFlag, EcsPoisonedFlag,
]

## Entities whose health it changed or checked on its last run.
var touched: int = 0

func label() -> StringName:
	return &"health"

func run(world: EcsWorld, delta: float) -> void:
	var loss: Dictionary = {}  # id -> health lost this run
	var gain: Dictionary = {}  # id -> health gained this run
	_count_stuns(world, delta)
	_effects(world, delta, loss, gain)
	_hits(world, loss)
	var inbox := world.get_singleton(EcsHealthSingleton) as EcsHealthSingleton
	if inbox != null:
		for change in inbox.changes:
			if change.amount > 0.0:
				gain[change.to] = float(gain.get(change.to, 0.0)) + change.amount
			else:
				loss[change.to] = float(loss.get(change.to, 0.0)) - change.amount
		inbox.changes.clear()

	touched = 0
	for id: int in _union(loss, gain):
		var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
		if health == null or world.has(id, EcsDyingFlag):
			continue
		touched += 1
		# Losses first: a body at zero never mends.
		health.value = maxf(health.value - float(loss.get(id, 0.0)), 0.0)
		if health.value <= 0.0:
			world.add(id, EcsDyingFlag.new())
			continue
		health.value = minf(health.value + float(gain.get(id, 0.0)), health.max_health)

func _count_stuns(world: EcsWorld, delta: float) -> void:
	for id in world.query([EcsStunnedFlag]):
		var stunned := world.get_component(id, EcsStunnedFlag) as EcsStunnedFlag
		stunned.left -= delta
		if stunned.left <= 0.0:
			world.remove(id, EcsStunnedFlag)

func _effects(world: EcsWorld, delta: float, loss: Dictionary, gain: Dictionary) -> void:
	for kind in kinds:
		var held := world.view([EcsHealthComponent, kind])
		if held.ids.is_empty():
			continue
		var flags := held.column(kind)
		var ended: Array[int] = []
		for k in held.ids.size():
			var id := held.ids[k]
			var effect := flags[k] as EcsHealthOverTimeFlag
			var amount := effect.rate * minf(delta, effect.left)
			if amount > 0.0:
				gain[id] = float(gain.get(id, 0.0)) + amount
			elif amount < 0.0:
				loss[id] = float(loss.get(id, 0.0)) - amount
			effect.left -= delta
			if effect.left <= 0.0:
				ended.append(id)
		# Removed after the loop: removing rebuilds the view.
		for id in ended:
			world.remove(id, kind)

func _hits(world: EcsWorld, loss: Dictionary) -> void:
	var combat := world.get_singleton(EcsCombatSingleton) as EcsCombatSingleton
	if combat == null:
		return
	for hit in combat.hits:
		if not world.has(hit.to, EcsHealthComponent) or world.has(hit.to, EcsDyingFlag):
			continue
		var taken := hit.amount
		var armor := world.get_component(hit.to, EcsArmorComponent) as EcsArmorComponent
		if armor != null:
			taken = maxf(taken - armor.reduction, armor.minimum)
		loss[hit.to] = float(loss.get(hit.to, 0.0)) + taken
		var hurt := world.get_component(hit.to, EcsHurtFlag) as EcsHurtFlag
		if hurt == null:
			hurt = world.add(hit.to, EcsHurtFlag.new()) as EcsHurtFlag
		hurt.by = hit.from
		if hit.stun > 0.0:
			var stunned := world.get_component(hit.to, EcsStunnedFlag) as EcsStunnedFlag
			if stunned == null:
				stunned = world.add(hit.to, EcsStunnedFlag.new()) as EcsStunnedFlag
			stunned.left = maxf(stunned.left, hit.stun)
		_afflict(world, hit.to, EcsBleedingFlag, hit.bleed_rate, hit.bleed_for)
		_afflict(world, hit.to, EcsPoisonedFlag, hit.poison_rate, hit.poison_for)
	combat.hits.clear()

## Raises or refreshes a timed effect: the worse rate and the longer time win, so
## repeated hits don't stack.
func _afflict(world: EcsWorld, id: int, kind: Script, per_second: float, seconds: float) -> void:
	if per_second <= 0.0 or seconds <= 0.0:
		return
	var effect := world.get_component(id, kind) as EcsHealthOverTimeFlag
	if effect == null:
		effect = world.add(id, kind.new()) as EcsHealthOverTimeFlag
		effect.left = 0.0
	effect.rate = minf(effect.rate, -per_second)
	effect.left = maxf(effect.left, seconds)

func _union(a: Dictionary, b: Dictionary) -> Array:
	var ids := a.keys()
	for id in b:
		if not a.has(id):
			ids.append(id)
	return ids
