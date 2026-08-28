class_name SimEntity
extends CharacterBody2D

## The bare base every sim entity is built from — creatures, props and items
## alike. It carries no behaviour of its own: what a thing *is* is decided
## entirely by which components SimEntityFactory attached from its blueprint.
##
## Scene layout (sim_entity.tscn):
##   SimEntity (CharacterBody2D)
##   ├── Sprite2D            texture/scale/tint set by SimSpriteDef
##   └── Body (Area2D)       this entity's PRESENCE — how other entities' sensors
##                           detect it, and what their actions reach (Phase 2)

## Blueprint id this entity was spawned from (e.g. &"type1").
var def_id: StringName = &""
## Where the entity was spawned. Wander leashes to this so nothing drifts off-map.
var home_position: Vector2 = Vector2.ZERO

## slot (StringName) -> component node. Populated by SimComponentDef.build_into().
var _components: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var body: Area2D = $Body

## Records a component under its slot key. Called by SimComponentDef.build_into()
## after the node has been added as a child.
func register_component(slot: StringName, node: Node) -> void:
	if _components.has(slot):
		push_warning("SimEntity '%s': slot '%s' registered twice" % [name, slot])
	_components[slot] = node

## The component occupying `slot`, or null. Cast at the call site:
## `entity.get_component(&"movement") as SimMovementComponent`.
func get_component(slot: StringName) -> Node:
	return _components.get(slot)

## Whether this entity has the component in `slot`. Capability = component
## presence: no movement slot means it physically cannot move.
func has_component(slot: StringName) -> bool:
	return _components.has(slot)

## Every slot this entity carries, for the debug overlay.
func component_slots() -> Array:
	return _components.keys()

## Actions this entity can PERFORM, unioned across its components (Phase 2).
func do_actions() -> Array[StringName]:
	return []

## Actions that can be performed ON this entity, unioned across its components
## (Phase 2). The interaction menu for A->B is `A.do_actions() & B.receive_actions()`.
func receive_actions() -> Array[StringName]:
	return []
