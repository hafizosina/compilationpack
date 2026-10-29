class_name EcsFlag
extends EcsComponent

## Base for every flag: something true of an entity right now, added and removed
## freely by the system that owns it. May carry runtime data, never `@export`.
## EcsWorld stores flags exactly like components.
