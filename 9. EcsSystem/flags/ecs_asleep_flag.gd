class_name EcsAsleepFlag
extends EcsFlag

## Asleep by choice. Carries no data.
##
## EcsHungerSystem and EcsEnergySystem both need to know whether an entity is
## asleep, and used to find out by reading the brain's `state` — two systems
## reading a third's private memory. This flag is the fact made public: the
## brain raises it with its SLEEP state and clears it on waking, and the other
## two read the flag without knowing a brain exists.
##
## A collapse is the forced kind, and is EcsCollapsedFlag. "Asleep" to hunger
## and energy is either flag.
