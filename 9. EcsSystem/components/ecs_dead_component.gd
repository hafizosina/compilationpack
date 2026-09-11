class_name EcsDeadComponent
extends EcsComponent

## Tag: out of the fight. Every combat query passes it as an exclude, so death
## removes an entity from the simulation's attention without destroying it —
## the corpse keeps its components, ready to be made harvestable in step 3.

func key() -> StringName:
	return &"dead"
