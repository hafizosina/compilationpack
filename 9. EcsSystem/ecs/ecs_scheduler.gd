class_name EcsScheduler
extends RefCounted

## The ordered system list. Run order IS the coordination mechanism — the brain
## writes a destination before movement walks toward it before node_sync draws
## where it ended up — so this list is the pipeline, written once in main.gd
## and read like a table of contents.
##
## ## Not every stage needs every tick
##
## A stage may declare how often it runs. `add(system, 3)` runs it every third
## tick — 20 Hz on a 60 Hz pipeline — and the reason that is safe is that every
## system in this module already takes `delta` and means it. A system that runs
## a third as often is handed three ticks' worth of delta, so hunger climbs at
## the same rate per second and the brain's pause lasts the same number of
## seconds. Nothing is scaled by hand.
##
## What changes is *latency*, not rate: a decision, or a fresh perception, can
## be up to `every` ticks late. For timer-based AI that is invisible; for
## movement and the view it is not, which is why those stay at every tick.
##
## **`phase` is what keeps the frame smooth.** Slow systems all landing on the
## same tick makes one heavy frame in three rather than three even ones — the
## sim gets cheaper on average and *worse* to look at. A system runs when
## `tick % every == phase`, so two systems at the same rate with different
## phases never share a tick. It also fixes read-after-write: give a consumer
## the phase just after its producer and it reads data one tick old, exactly as
## it did at full rate.

var _systems: Array[EcsSystem] = []
var _every: PackedInt32Array = PackedInt32Array()
var _phase: PackedInt32Array = PackedInt32Array()
## Delta banked since each system last ran, so a stage that runs every third
## tick is handed the whole three ticks rather than one of them.
var _accum: PackedFloat32Array = PackedFloat32Array()
var _tick: int = 0

## Appends a system and returns self, so a pipeline reads as one chained
## statement in the order it runs.
##
## `every` is in ticks — 1 is every tick, 3 is 20 Hz on a 60 Hz pipeline.
## `phase` picks which of those ticks it lands on, and must be less than
## `every` or the system never runs.
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

## One tick: every system that is due, in order, each handed the time that has
## passed since *it* last ran.
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

## How often each system runs, in ticks, for anything reporting on the pipeline.
func intervals() -> PackedInt32Array:
	return _every
