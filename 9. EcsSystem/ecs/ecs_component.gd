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

## Stable name for this component kind. Override in every subclass.
func key() -> StringName:
	return &""
