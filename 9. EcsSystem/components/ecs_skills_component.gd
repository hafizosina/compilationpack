class_name EcsSkillsComponent
extends EcsComponent

## The skills it knows and their timers. EcsSkillSystem runs them.

## Skills it can cast.
@export var skills: Array[EcsSkillDef] = []

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
