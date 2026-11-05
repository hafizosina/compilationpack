class_name EcsSwingFlag
extends EcsFlag

## Swinging its weapon. Raised by whoever starts the swing (control for an attack, strike for
## a skill); EcsWeaponSystem advances it, poses the weapon from it and removes it at the end.

## Facing angle the swing is centred on, in radians.
var direction: float = 0.0
## Degrees it sweeps.
var arc: float = 130.0
## Seconds it lasts.
var duration: float = 0.16
## Seconds so far.
var elapsed: float = 0.0
