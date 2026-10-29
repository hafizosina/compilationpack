class_name EcsScheduler
extends RefCounted

## Runs systems in order. A system can run every `every` ticks; it runs when
## `tick % every == phase` and receives all the delta since its last run.
## Give slow systems different phases so they don't share a tick.

var _systems: Array[EcsSystem] = []
var _every: PackedInt32Array = PackedInt32Array()
var _phase: PackedInt32Array = PackedInt32Array()
## Delta accumulated since each system last ran.
var _accum: PackedFloat32Array = PackedFloat32Array()
var _tick: int = 0

## Appends a system and returns self for chaining. `every` is in ticks
## (3 = 20 Hz at 60 Hz); `phase` must be less than `every`.
func add(system: EcsSystem, every: int = 1, phase: int = 0) -> EcsScheduler:
	if system == null:
		push_error("EcsScheduler: refusing to add a null system")
		return self
	if every < 1:
		push_error("EcsScheduler: '%s' asked for every=%d; a stage runs at least once"
			% [system.label(), every])
		every = 1
	if phase < 0 or phase >= every:
		push_error("EcsScheduler: '%s' asked for phase %d of every %d — it would never run"
			% [system.label(), phase, every])
		phase = 0
	_systems.append(system)
	_every.append(every)
	_phase.append(phase)
	_accum.append(0.0)
	return self

## Runs every system that is due this tick, in order.
func run_all(world: EcsWorld, delta: float) -> void:
	for i in _systems.size():
		_accum[i] += delta
		if _tick % _every[i] != _phase[i]:
			continue
		_systems[i].run(world, _accum[i])
		_accum[i] = 0.0
	_tick += 1

func systems() -> Array[EcsSystem]:
	return _systems

## How often each system runs, in ticks.
func intervals() -> PackedInt32Array:
	return _every
