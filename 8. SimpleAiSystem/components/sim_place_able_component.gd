class_name SimPlaceAbleComponent
extends SimComponent

## Target-side affordance: this entity can be put back down into the world as a
## standing thing. Offers the `place_item` stub.
##
## DECLARED, NOT IMPLEMENTED. Placing is not wired up; the blueprint snapshot an
## inventory holds is already enough to respawn one through the factory, so this
## is where that will hang. No blueprint carries it.

func slot() -> StringName:
	return &"placeable"

func stubs() -> Array[StringName]:
	return [&"place_item"]
