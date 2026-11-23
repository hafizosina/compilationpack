class_name EcsEconomyCatalog
extends Resource

## Every building role, resource, town character and building group, looked up by key.

@export var roles: Array[EcsSettlementRoleDef] = []
@export var resources: Array[EcsResourceDef] = []
@export var characters: Array[EcsSettlementCharacterDef] = []
## Building groups, in the order their district points are placed.
@export var groups: Array[EcsGroupDef] = []

## The role keyed `key`, or null.
func role(key: StringName) -> EcsSettlementRoleDef:
	for r in roles:
		if r.key == key:
			return r
	return null

## The resource keyed `key`, or null.
func resource(key: StringName) -> EcsResourceDef:
	for r in resources:
		if r.key == key:
			return r
	return null

## The group keyed `key`, or null.
func group(key: StringName) -> EcsGroupDef:
	for g in groups:
		if g.key == key:
			return g
	return null
