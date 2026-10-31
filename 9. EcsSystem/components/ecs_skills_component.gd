class_name EcsSkillsComponent
extends EcsComponent

## The skills it knows and their timers. EcsSkillSystem runs them. Every animal gets the
## default set; `swaps` replace defaults with the same id, or add to them.

## This kind's own versions of skills.
@export var swaps: Array[EcsSkillDef] = []

## The skills it can cast: the defaults with `swaps` applied. Filled by EcsSkillSystem.
var skills: Array[EcsSkillDef] = []
## Whether `skills` has been filled.
var resolved: bool = false

## Skill id -> seconds until it can be cast again.
var cooldown_left: Dictionary = {}
## Skill id -> seconds left while active; held skills sit at 0.
var active_left: Dictionary = {}

func key() -> StringName:
	return &"skills"

func describe() -> Dictionary:
	var lines := {}
	for skill in skills:
		if active_left.has(skill.id):
			lines[String(skill.id)] = "active"
		elif cooldown_left.get(skill.id, 0.0) > 0.0:
			lines[String(skill.id)] = "%.1fs" % cooldown_left[skill.id]
		else:
			lines[String(skill.id)] = "ready"
	return {"tab": &"own", "lines": lines}
