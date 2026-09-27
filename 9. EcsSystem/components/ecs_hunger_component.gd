class_name EcsHungerComponent
extends EcsComponent

## How fed it is, and at what points that starts to matter.
##
## **The number is `fullness`, not hunger.** It starts at `max_fullness`, drains
## toward zero, and zero is starving — the same shape as EcsHealthComponent, so
## the two bars an entity carries both deplete, both read "more is better", and
## both mean trouble at the bottom. The class keeps the name `EcsHungerComponent`
## because hunger is what the thing is *about*; the field is named for what it
## actually counts so no call site has to hold the inversion in its head.
##
## It is the *reason* the rest of the loop exists. Before it, a creature foraged
## because EcsLowBrainSystem's food rung said to and stopped when its bag was
## full — motion with no motive. Now the rung asks this first, so gathering is
## something a hungry animal does and a fed one does not.
##
## Carrying this component is the whole of "this entity needs to eat". A berry
## bush has none and no rung ever asks.

## How fast fullness drains, in points per second, while awake.
@export var drain: float = 2.0
## What fraction of that it drains while asleep or collapsed.
##
## A scale rather than a second rate, so "slower asleep" survives retuning
## `drain` and cannot quietly invert. 0 makes sleeping free; 1 makes it cost the
## same as being awake, which is the behaviour this replaced.
##
## It must stay above 0 for `EcsLowBrainSystem`'s wake-on-starving rule to be
## reachable at all: a sleeper that never empties never has a reason to get up
## before it is rested.
@export var asleep_drain_scale: float = 0.4
## Full. Also the ceiling a meal cannot push past.
@export var max_fullness: float = 100.0
## Empty enough to go and fetch food it can see. The brain's SEEK_FOOD rung
## declines *above* this, so a fed creature wanders past a berry.
@export var forage_below: float = 65.0
## Empty enough to eat what it already has at hand.
##
## For a carrier this sits **below** `forage_below`: it gathers while peckish,
## carries, and eats once properly empty, so both rungs are visible in play. For
## a grazer — something with no inventory to stockpile into — it sits *above*,
## so anything it walked to gets eaten on arrival rather than stood over. That
## one relation is the whole difference between hoarding and grazing, and it is
## an authored value in a `.tres`, not a code change.
@export var eat_below: float = 40.0
## Health lost per second while fullness sits at zero. Starving does nothing at
## all to an entity with no EcsHealthComponent.
@export var starve_damage: float = 5.0
## Fed enough to mend. Above this, health comes back at `heal_rate`.
##
## Set so one meal reaches it from either creature's eating threshold — a berry
## is worth 40, a carrier eats at 40 and a grazer at 70, so both clear 70 after
## a single berry. Raise it and eating stops paying for itself.
@export var heal_above: float = 70.0
## Health regained per second while above `heal_above`. Deliberately slower than
## `starve_damage`: going hungry should cost more than being fed repays.
@export var heal_rate: float = 1.5

## Only the reading goes on the inspector's Entity tab, and the component gets
## no tab of its own.
const INSPECT_ON_ENTITY_TAB := {"fullness": [&"fullness", &"max_fullness"]}

## How fed it is right now. Runtime state: `max_fullness` fed, 0 starving.
var fullness: float = 100.0

func key() -> StringName:
	return &"hunger"
