class_name EcsLowBrainComponent
extends EcsComponent

## What the creature is doing, and what it committed to in order to do it.
##
## Named for its rank rather than its behaviour: it is the *low* brain because
## the plan's step 7 puts a planner above it, not because it is simple. What it
## holds is a small state machine's worth of memory, and EcsLowBrainSystem is
## the machine.
##
## ## Why this has state at all
##
## It used to be a pause timer, and deciding was split across two systems that
## each re-derived everything from scratch every tick: EcsForageSystem picked
## food, this picked a random point, and priority was which line of main.gd
## they sat on. That worked and it read well, but it left a creature with no
## memory between ticks beyond `EcsMovementComponent.has_destination` — one
## borrowed boolean. Nothing could persist ("I am going to *that* berry"),
## nothing could be interrupted (a rung may fill an empty destination slot,
## never take a full one), and a threshold crossed back and forth flickered the
## creature between rungs on consecutive ticks.
##
## `state` and `target` are that missing memory. A decision now survives the
## tick that made it, which is what makes it a decision rather than a reflex.
##
## Carrying this component is the whole of "this entity decides for itself".

## What it is doing now. The ladder lives in EcsLowBrainSystem's run order,
## highest rung first; this records which rung won.
enum State {
	IDLE,       ## Standing still, waiting out `pause_left`.
	WANDER,     ## Walking to a point it picked for no reason.
	SEEK_FOOD,  ## Walking to `target`, which it means to pick up.
	TAKE,       ## Standing still, putting something within reach into its bag.
	EAT,        ## Standing still, eating something out of its own bag.
	SLEEP,      ## Down, getting energy back. Chosen, or forced by a collapse.
}

## Display names for `state`, in enum order. A constant and not a method,
## because components stay method-free — the debug overlay indexes it.
const STATE_NAMES: Array[String] = ["idle", "wander", "seek food", "taking", "eating", "sleeping"]

## How far from its current spot a wander destination may be picked.
@export var radius: float = 260.0
## Shortest and longest idle pause between legs, in seconds.
@export var pause_min: float = 0.4
@export var pause_max: float = 2.5

## Seconds left of the current pause. Runtime state, not authored.
var pause_left: float = 0.0
## Which rung is currently running. Runtime state.
var state: State = State.IDLE
## The entity this brain committed to, or NO_ENTITY. Only SEEK_FOOD sets it,
## and it is cleared the moment the commitment ends — arrived, given up, or the
## target stopped being something to walk to.
var target: int = EcsWorld.NO_ENTITY

## Not shown in the inspector's entity detail.
const INSPECT_HIDDEN := true

func key() -> StringName:
	return &"low_brain"
