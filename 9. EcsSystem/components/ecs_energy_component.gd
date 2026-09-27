class_name EcsEnergyComponent
extends EcsComponent

## How rested it is, and the thresholds that turn that into sleeping.
##
## A **reserve**, like fullness and health: `max_energy` is rested, 0 is
## exhausted, and a short bar is bad news on all three. Being awake costs;
## sleeping repays.
##
## Carrying this component is the whole of "this entity tires". A berry bush has
## none and never sleeps, and nothing had to tell it not to.

## Full. Also the ceiling rest cannot push past.
@export var max_energy: float = 100.0
## Cost per second of simply being awake.
##
## Without it a well-fed creature that never moves never tires, and nothing
## would ever sleep in a world with enough food. Set it to 0 and "only movement
## tires" becomes true — a `.tres` edit, not a code change.
@export var drain_idle: float = 0.5
## Extra cost per second while actually moving, on top of `drain_idle`.
@export var drain_moving: float = 1.0
## Energy regained per second while asleep or collapsed.
@export var restore: float = 1.0
## At or below this, the brain may choose to sleep — but only if nothing it
## wants more is available. Food outranks rest.
@export var rest_at: float = 30.0
## A voluntary sleep ends on its own here.
##
## Deliberately far above `rest_at`: that gap is the hysteresis, and it is what
## stops a creature flickering between sleeping and waking around one line.
@export var wake_at: float = 100.0
## Where the collapse lock lifts. Below `wake_at`, so a creature that collapsed
## comes round still tired and goes on sleeping — voluntarily this time, and so
## interruptible by starving.
@export var collapse_release: float = 50.0
## Health taken once, at the moment of collapse. Nothing at all to an entity
## with no EcsHealthComponent, the same way starving is nothing to one.
@export var collapse_damage: float = 20.0
## The range a new entity's starting energy is drawn from, as fractions of
## `max_energy`. Without a spread every animal is born equally rested with the
## same drain, and the whole population falls asleep at once. 1.0 / 1.0 — the
## default — is no spread at all.
@export_range(0.0, 1.0) var start_min: float = 1.0
@export_range(0.0, 1.0) var start_max: float = 1.0

## Only the reading goes on the inspector's Entity tab, labelled — a bare
## `value` would be ambiguous there beside health's.
const INSPECT_ON_ENTITY_TAB := {"energy": &"value"}

## How rested it is right now. Runtime state: `max_energy` rested, 0 exhausted.
## Full until EcsEnergySystem first sees the entity and rolls it.
var value: float = 100.0
## Whether the starting value has been rolled. Runtime state. A record keeps it,
## so an animal put back into the world keeps its energy rather than re-rolling.
## A placement that authors its own `value` must set this true beside it, or the
## roll overwrites the authored number on the first tick (world1.tres does).
var rolled: bool = false

func key() -> StringName:
	return &"energy"
