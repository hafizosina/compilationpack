class_name EcsLowBrainComponent
extends EcsComponent

## State for EcsLowBrainSystem's state machine.

enum State {
	IDLE,       ## Standing still, waiting out `pause_left`.
	WANDER,     ## Walking to a random point.
	SEEK_FOOD,  ## Walking to `target` to get it.
	TAKE,       ## Picking up something in reach.
	EAT,        ## Eating something in reach or in its bag.
	SLEEP,      ## Asleep, by choice or by collapse.
	HUNT,       ## Chasing `target` to attack it.
	ATTACK,     ## Attacking `target`, which is in reach.
	HARVEST,    ## Harvesting `target`, which is in reach.
	FLEE,       ## Running from the danger's last threat.
	HIDE,       ## Walking to cover `target`, stopping once in it.
	AMBUSH,     ## Hiding in cover `target`, waiting out `pause_left` for prey.
	POUNCE,     ## Dashing at `target`; becomes HUNT once the dash starts.
	SCAN,       ## Standing still, scanning for `pause_left`.
	SEEK_WATER, ## Walking to water `target` to drink.
	DRINK,      ## Drinking from `target`, which is in reach, until full.
}

## Display names for `state`, in enum order.
const STATE_NAMES: Array[String] = ["idle", "wander", "seek food", "taking", "eating", "sleeping",
	"hunting", "attacking", "harvesting", "fleeing", "to cover", "ambushing", "pouncing",
	"scanning", "seek water", "drinking"]

## How far away a wander destination may be.
@export var radius: float = 260.0
## Shortest and longest idle pause between wanders, in seconds.
@export var pause_min: float = 0.4
@export var pause_max: float = 2.5

## Seconds left of the current pause, ambush or scan.
var pause_left: float = 0.0
## Current state.
var state: State = State.IDLE
## The entity it is committed to, or NO_ENTITY.
var target: int = EcsWorld.NO_ENTITY

func key() -> StringName:
	return &"low_brain"

func describe() -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
