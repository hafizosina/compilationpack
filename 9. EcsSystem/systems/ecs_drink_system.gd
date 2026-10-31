class_name EcsDrinkSystem
extends EcsSystem

## Executes EcsDrinkIntentFlag: while the named water is drinkable and in reach,
## hydration rises at its `rate`, up to full.

func label() -> StringName:
	return &"drink"

func run(world: EcsWorld, delta: float) -> void:
	var drinkers := world.view([EcsDrinkIntentFlag, EcsThirstComponent, EcsActionComponent],
		[EcsDyingFlag])
	var intents := drinkers.column(EcsDrinkIntentFlag)
	var thirsts := drinkers.column(EcsThirstComponent)
	var actions := drinkers.column(EcsActionComponent)
	for k in drinkers.ids.size():
		var water := (intents[k] as EcsDrinkIntentFlag).target_id
		if not (actions[k] as EcsActionComponent).reached.has(water):
			continue
		var drinkable := world.get_component(water, EcsDrinkableComponent) as EcsDrinkableComponent
		if drinkable == null:
			continue
		var thirst := thirsts[k] as EcsThirstComponent
		thirst.hydration = minf(thirst.hydration + drinkable.rate * delta, thirst.max_hydration)
