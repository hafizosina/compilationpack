class_name EcsFlag
extends EcsComponent

## Base for every flag: what is true of an entity *now*, as opposed to a
## component, which is what the entity *is*.
##
## A component is present from spawn to death — the blueprint decides the set,
## and a wall that gains movement is no longer a wall, which is a kill and a
## spawn rather than an `add()`. A flag is added and removed freely by the
## system that owns it, mid-game, as often as the fact changes.
##
## A flag may carry data (an intent names its target), but never authored data:
## no `@export`, because nothing about a flag is decided before the game starts.
## Everything it holds is written by the system that adds it.
##
## It is a guideline, not an enforced rule — EcsWorld treats flags and components
## identically, so queries, `has()` and `remove()` work the same on both. Break
## it when there is a good reason, and write the reason down where it breaks.
## The one place the difference is visible is the inspector, which lists an
## entity's flags together on one tab rather than one tab each.
