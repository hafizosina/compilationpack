class_name EcsEconomyCatalog
extends Resource

## Every building role and town character, looked up by key.

@export var roles: Array[EcsSettlementRoleDef] = []
@export var characters: Array[EcsSettlementCharacterDef] = []
## Roles added, in order of preference, while a town can't feed itself.
@export var food_roles: Array[StringName] = []

## The role keyed `key`, or null.
func role(key: StringName) -> EcsSettlementRoleDef:
	for r in roles:
		if r.key == key:
			return r
	return null
