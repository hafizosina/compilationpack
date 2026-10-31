class_name EcsHit
extends RefCounted

## One hit landed this tick, from attacker to target.

var from: int = EcsWorld.NO_ENTITY
var to: int = EcsWorld.NO_ENTITY
## Damage before the target's armour.
var amount: float = 0.0
var critical: bool = false
## Seconds it stuns the target; 0 for none.
var stun: float = 0.0
