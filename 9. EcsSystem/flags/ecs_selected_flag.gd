class_name EcsSelectedFlag
extends EcsFlag

## Selected for the inspector and live edits. Any number of entities may have it.

func key() -> StringName:
	return &"selected"
