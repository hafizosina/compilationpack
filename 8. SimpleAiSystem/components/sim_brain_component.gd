class_name SimBrainComponent
extends SimComponent

## Base for every brain. `brain` is a component TYPE — the slot — and each
## concrete brain is one way of filling it: SimBrainFSMComponent now, a GOAP
## planner later. Code that wants "the brain" asks for the slot and gets
## whichever implementation this entity was built with.
##
## **An entity may hold only one brain.** Two things deciding where the same
## legs go is not a mode worth supporting, so SimBrainDef refuses to build a
## second one rather than letting them fight.

func slot() -> StringName:
	return &"brain"

## Whether this brain is currently deciding. FatigueComponent switches it off
## during collapse without knowing which brain it is switching off.
func is_thinking() -> bool:
	return is_processing()
