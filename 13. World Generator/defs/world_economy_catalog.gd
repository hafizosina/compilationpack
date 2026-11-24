class_name WorldEconomyCatalog
extends Resource

## Every building role, resource, town character and building group, looked up by key.

@export var roles: Array[WorldSettlementRoleDef] = []
@export var resources: Array[WorldResourceDef] = []
@export var characters: Array[WorldSettlementCharacterDef] = []
## Building groups, in the order their district points are placed.
@export var groups: Array[WorldGroupDef] = []

## The role keyed `key`, or null.
func role(key: StringName) -> WorldSettlementRoleDef:
	for r in roles:
		if r.key == key:
			return r
	return null

## The resource keyed `key`, or null.
func resource(key: StringName) -> WorldResourceDef:
	for r in resources:
		if r.key == key:
			return r
	return null

## The group keyed `key`, or null.
func group(key: StringName) -> WorldGroupDef:
	for g in groups:
		if g.key == key:
			return g
	return null
