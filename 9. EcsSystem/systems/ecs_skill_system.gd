class_name EcsSkillSystem
extends EcsSystem

## Executes EcsCastIntentFlag and runs skill timers. The only writer of a skill's
## effect flag: it adds `make_effect()` when a skill starts and removes it when it
## ends. A timed skill ends after `duration`; a held one when its intent is gone
## or `can_start` stops holding. The cooldown starts when a skill ends. A cast that
## is unknown, active, cooling or refused by `can_start` does nothing.

func label() -> StringName:
	return &"skill"

func run(world: EcsWorld, delta: float) -> void:
	var view := world.view([EcsSkillsComponent], [EcsDyingFlag])
	var columns := view.column(EcsSkillsComponent)
	for k in view.ids.size():
		var known := columns[k] as EcsSkillsComponent
		# Nothing running: only a cast could change it, and casts are started below.
		if known.cooldown_left.is_empty() and known.active_left.is_empty():
			continue
		var id := view.ids[k]
		for skill_id in known.cooldown_left.keys():
			known.cooldown_left[skill_id] -= delta
			if known.cooldown_left[skill_id] <= 0.0:
				known.cooldown_left.erase(skill_id)

		var cast := world.get_component(id, EcsCastIntentFlag) as EcsCastIntentFlag
		var asked: StringName = cast.skill if cast != null else &""
		for skill in known.skills:
			if not known.active_left.has(skill.id):
				continue
			if skill.duration > 0.0:
				known.active_left[skill.id] -= delta
				if known.active_left[skill.id] <= 0.0:
					_end(world, id, known, skill)
			elif asked != skill.id or not skill.can_start(world, id):
				_end(world, id, known, skill)

	var casting := world.view([EcsCastIntentFlag, EcsSkillsComponent], [EcsDyingFlag])
	var casts := casting.column(EcsCastIntentFlag)
	var knowns := casting.column(EcsSkillsComponent)
	for k in casting.ids.size():
		var id := casting.ids[k]
		var known := knowns[k] as EcsSkillsComponent
		var asked := (casts[k] as EcsCastIntentFlag).skill
		if known.active_left.has(asked) or known.cooldown_left.has(asked):
			continue
		var wanted := EcsSkillDef.find(known.skills, asked)
		if wanted != null and wanted.can_start(world, id):
			known.active_left[asked] = wanted.duration
			world.add(id, wanted.make_effect())

func _end(world: EcsWorld, id: int, known: EcsSkillsComponent, skill: EcsSkillDef) -> void:
	known.active_left.erase(skill.id)
	world.remove(id, skill.make_effect().get_script())
	if skill.cooldown > 0.0:
		known.cooldown_left[skill.id] = skill.cooldown
