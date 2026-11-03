class_name EcsEdit
extends RefCounted

## A request to set one field of one component on some entities, carried out by
## EcsEditSystem at its next run.

## Entities to change; dead ones and ones without the component are skipped.
var ids: Array[int] = []
## Component key, as its `key()` returns it.
var component: StringName = &""
## Field name on that component.
var field: StringName = &""
## The new value; skipped where it can't take the field's type.
var value: Variant = null
