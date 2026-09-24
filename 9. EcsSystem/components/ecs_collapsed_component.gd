class_name EcsCollapsedComponent
extends EcsComponent

## Tag: this entity ran out of energy and has no say until it comes round.
## Carries no data — presence is the lock.
##
## It is how EcsEnergySystem tells the brain "not now" without writing the
## brain's component, the same line EcsHungerSystem keeps by spending health and
## never touching the brain. The brain reads the tag and yields; the energy
## system adds it at zero and removes it at `collapse_release`. Neither calls
## the other.

func key() -> StringName:
	return &"collapsed"
