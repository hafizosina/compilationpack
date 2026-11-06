class_name EcsSkillCostSystem
extends EcsSystem

## Pays a skill's `cost` in the tick it starts, from any bar the caster has (health,
## fullness, energy, hydration, stamina, mana: any component declaring `BAR_VALUE`), and
## drops a cast that can't be paid for. Spending goes to the bar's `spent`, which the bar's
## own system applies. Runs just before EcsSkillSystem.

var _defaults: EcsSkillSet

func _init(defaults: EcsSkillSet = EcsSkillSystem.DEFAULTS) -> void:
	_defaults = defaults

func label() -> StringName:
	return &"skill_cost"

func run(world: EcsWorld, _delta: float) -> void:
	for id in world.query([EcsSpentFlag]):
		world.remove(id, EcsSpentFlag)
	var casting := world.view([EcsCastIntentFlag, EcsSkillsComponent], [EcsDyingFlag])
	var casts := casting.column(EcsCastIntentFlag)
	var knowns := casting.column(EcsSkillsComponent)
	for k in casting.ids.size():
		var id := casting.ids[k]
		var known := knowns[k] as EcsSkillsComponent
		var asked := (casts[k] as EcsCastIntentFlag).skill
		var skill := _skill_for(known, asked)
		if skill == null or skill.cost.is_empty() or known.active_left.has(asked) \
				or known.cooldown_left.has(asked) or not skill.can_start(world, id):
			continue
		var bars := _bars_of(world, id)
		var affordable := true
		for bar_key: StringName in skill.cost:
			var bar: EcsComponent = bars.get(bar_key)
			if bar == null or float(bar.get(bar.get(&"BAR_VALUE"))) - float(bar.get(&"spent")) \
					< skill.cost[bar_key]:
				affordable = false
				break
		if not affordable:
			world.remove(id, EcsCastIntentFlag)
			continue
		for bar_key: StringName in skill.cost:
			var bar: EcsComponent = bars[bar_key]
			bar.set(&"spent", float(bar.get(&"spent")) + skill.cost[bar_key])
		if not world.has(id, EcsSpentFlag):
			world.add(id, EcsSpentFlag.new())

## The skill `asked` names, as EcsSkillSystem will resolve it: a swap, else a default.
func _skill_for(known: EcsSkillsComponent, asked: StringName) -> EcsSkillDef:
	if known.resolved:
		return EcsSkillDef.find(known.skills, asked)
	var swap := EcsSkillDef.find(known.swaps, asked)
	return swap if swap != null else EcsSkillDef.find(_defaults.skills, asked)

## `id`'s bars by key: enabled components that declare `BAR_VALUE`.
static func _bars_of(world: EcsWorld, id: int) -> Dictionary:
	var bars := {}
	for component in world.components_of(id):
		if component.enabled and component.get(&"BAR_VALUE") != null:
			bars[component.key()] = component
	return bars
