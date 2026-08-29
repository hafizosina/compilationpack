class_name SimEntity
extends CharacterBody2D

## The bare base every sim entity is built from — creatures, props and items
## alike. It carries no behaviour of its own: what a thing *is* is decided
## entirely by which components SimEntityFactory attached from its blueprint.
##
## Scene layout (sim_entity.tscn):
##   SimEntity (CharacterBody2D)
##   ├── Sprite2D      texture/scale/tint set by SimSpriteDef
##   └── BodyShape     this entity's PRESENCE — how other entities' sensors detect
##                     it, and what their actions reach (Phase 2)
##
## The CharacterBody2D *is* the presence: an Area2D sensor picks entities up
## through `body_entered` / `get_overlapping_bodies()`, so no second Area2D is
## needed here. `collision_layer` keeps an entity detectable while
## `collision_mask = 0` stops the population from shoving itself around.
## A Sensor's detection radius and an Action's reach are their own areas on the
## *actor*, and vary per def — they are never this shape.

## Blueprint id this entity was spawned from (e.g. &"type1").
var def_id: StringName = &""
## slot (StringName) -> component node. Populated by SimComponentDef.build_into().
var _components: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
## Extent of the entity's presence. The shape is a sub-resource shared by every
## instance of the scene, so a def that resizes it per entity must duplicate()
## it first — the same rule SimComponentDef states for live mutable state.
@onready var body_shape: CollisionShape2D = $BodyShape

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

## A formatted snapshot for the inspector panel: the entity's own facts plus
## whatever each component chooses to expose through its describe().
func describe() -> Dictionary:
	var reported := {}
	for key in _components:
		var node: Node = _components[key]
		# The sprite slot registers the bare Sprite2D from the scene, which has
		# no describe() — guard rather than assume every slot is a SimComponent.
		if not node.has_method("describe"):
			continue
		var fields: Dictionary = node.describe()
		if fields.is_empty():
			continue
		# Label and fields both come from the component — the entity aggregates,
		# it never decides how a component presents itself.
		reported[String(key)] = {
			"label": node.describe_label() if node.has_method("describe_label") else String(key),
			"fields": fields,
		}
	var slot_names: Array[String] = []
	for key in _components:
		slot_names.append(String(key))
	return {
		"name": name,
		"type": String(def_id),
		"position": "%.0f, %.0f" % [global_position.x, global_position.y],
		"slots": ", ".join(slot_names),
		"components": reported,
	}

## Actions this entity can PERFORM, unioned across its components.
## Phase 2 fills these in; unused in this prototype, but they are the declared
## interface for the do-intersect-receive resolver (COLONY_SIM_CONCEPT.md §2),
## not leftovers — leave them.
func do_actions() -> Array[StringName]:
	return []

## Actions that can be performed ON this entity, unioned across its components
## (Phase 2). The interaction menu for A->B is `A.do_actions() & B.receive_actions()`.
func receive_actions() -> Array[StringName]:
	return []
