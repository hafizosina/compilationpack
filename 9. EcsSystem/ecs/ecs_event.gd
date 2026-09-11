class_name EcsEvent
extends RefCounted

## Base for the transient records systems use to talk to each other within one
## frame — a DamageEvent is written by the attack system and read by the damage,
## crit and durability systems, then dropped when the scheduler finishes the
## frame.
##
## Deliberately RefCounted rather than Resource: events are never authored in a
## .tres and never persist, so they stay out of the data-file world entirely.
