class_name EcsStaminaComponent
extends EcsPoolComponent

## Stamina, the HUD's energy bar: sprinting drains it, physical skills cost it.

func key() -> StringName:
	return &"stamina"
