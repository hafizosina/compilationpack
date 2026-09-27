extends RefCounted

## Presenter for a component a person clicking an animal does not want to read —
## physics and view plumbing, the brain's internals. It shows nothing; the
## component is still named on the Entity tab's `components` line.
##
## Presenter contract, shared by every script in this folder: a static
## `present(component)` returning `{"tab": &"entity" | &"own" | &"hidden",
## "lines": {label: text}}`, plus an optional `"title": {"name", "type"}`.
## EcsInspectSystem knows the contract and nothing about any component.

static func present(_component: EcsComponent) -> Dictionary:
	return {"tab": &"hidden", "lines": {}}
