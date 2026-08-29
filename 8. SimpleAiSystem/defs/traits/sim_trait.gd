class_name SimTrait
extends Resource

## A behaviour modifier on SimBrainComponent. Every creature shares one brain;
## traits are what make two of them act differently without a second brain,
## a subclass, or an `if` in the brain.
##
## The brain calls each hook on every trait it carries, in order. A trait that
## does not care about a hook simply does not override it, so adding a hook here
## never breaks existing traits. No trait means default behaviour — an entity
## with no flock trait wanders randomly, and nothing has to check for that.
##
## `brain` is deliberately untyped: SimBrainComponent holds an Array of these,
## so annotating it would make the two scripts reference each other in a cycle.
## Reach the world through `brain.entity`, `brain.sensor()` and the brain's
## public tuning fields.

## Name shown in the inspector's Brain tab.
func trait_name() -> String:
	return "Trait"

## Adjusts the offset the brain is about to wander by, measured from the
## entity's current position. Return `offset` untouched to abstain.
func adjust_wander(_brain, offset: Vector2) -> Vector2:
	return offset

## Extra field -> value pairs merged into the Brain tab. Same contract as
## SimComponent.describe(): already formatted, {} to stay out.
func describe(_brain) -> Dictionary:
	return {}
