class_name EcsComponent
extends Resource

## Base for every component. A component is DATA: exported fields and nothing
## else. No apply(), no use(), no tick(). All behaviour lives in an EcsSystem.
##
## `key()` is the single exception and it is *identity*, not behaviour — a
## stable name for the type so a .tres placement can address it in an override
## block and the HUD can label it. Storage and queries key on the script object
## itself (`EcsPositionComponent`, never `"position"`), so a mistyped query is a
## parse error rather than a silently empty result.
##
## A subclass may also declare `const NODE_KIND: StringName`, naming a kind from
## EcsConst, to say that an entity carrying it needs a node of that kind.
## EcsEntityManager reads the constant at spawn and builds one. It is a
## constant and not a method for the reason above: the component states what it
## implies and still does nothing. Nothing gives a component the node back —
## systems look nodes up on the manager by entity id.

## Stable name for this component kind. Override in every subclass.
func key() -> StringName:
	return &""
