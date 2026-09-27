extends RefCounted

## Presenter for EcsEnergyComponent: its reading against its ceiling, on the
## Entity tab.

static func present(component: EcsComponent) -> Dictionary:
	var energy := component as EcsEnergyComponent
	return {"tab": &"entity",
		"lines": {"energy": "%d/%d" % [roundi(energy.value), roundi(energy.max_energy)]}}
