class_name EcsBrokenComponent
extends EcsComponent

## Tag: this item has worn out. Carries no data — presence is the fact. The
## durability system adds it and strips the item's EcsDamageComponent, so the
## attack system falls back to unarmed on its own, with no "is the weapon
## broken" branch anywhere.

func key() -> StringName:
	return &"broken"
