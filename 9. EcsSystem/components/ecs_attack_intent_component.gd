class_name EcsAttackIntentComponent
extends EcsComponent

## "I want to hit that." Written by whatever is deciding, consumed and removed
## by EcsAttackSystem in the same frame. The intent component is the seam
## between deciding and doing: the decider needs to know nothing about weapons,
## armour or durability, and the executor needs to know nothing about why.

var target_id: int = EcsWorld.NO_ENTITY

func key() -> StringName:
	return &"attack_intent"
