extends VBoxContainer

## Module 9's Outliner tab: every entity, grouped by type and filtered by a
## search. Click selects, shift-click adds or removes, double-click also centres
## the camera. Rows change in place, so scroll and folding survive each update.

@onready var _search: LineEdit = %Search
@onready var _tree: Tree = %EntityTree
@onready var _summary: Label = %Summary

## Latest list from the census: `{id, name, type}`.
var _entries: Array = []
## Type -> its group row, and id -> its row.
var _groups: Dictionary = {}
var _rows: Dictionary = {}

func _ready() -> void:
	_tree.create_item()
	_tree.hide_root = true
	EventBus.ecs_entities_listed.connect(func(entries: Array) -> void:
		_entries = entries
		if is_visible_in_tree():
			_refresh())
	_search.text_changed.connect(func(_text: String) -> void: _refresh())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refresh())
	_tree.item_mouse_selected.connect(func(_at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_pick(false))
	_tree.item_activated.connect(func() -> void: _pick(true))

func _pick(focus: bool) -> void:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var id: int = item.get_metadata(0)
	EventBus.ecs_entity_pick_requested.emit(id, Input.is_key_pressed(KEY_SHIFT))
	if focus:
		EventBus.ecs_camera_focus_requested.emit(id)

## Adds, renames and removes rows to match `_entries` under the search.
func _refresh() -> void:
	var query := _search.text.strip_edges().to_lower()
	var wanted: Dictionary = {}
	var counts: Dictionary = {}
	for entry in _entries:
		var type: String = entry["type"]
		var entity_name: String = entry["name"]
		if not query.is_empty() and not entity_name.to_lower().contains(query) \
				and not type.to_lower().contains(query):
			continue
		wanted[entry["id"]] = entry
		counts[type] = counts.get(type, 0) + 1

	for id in _rows.keys():
		if not wanted.has(id):
			(_rows[id] as TreeItem).free()
			_rows.erase(id)
	for type in _groups.keys():
		if not counts.has(type):
			(_groups[type] as TreeItem).free()
			_groups.erase(type)

	var types := counts.keys()
	types.sort()
	for type in types:
		if not _groups.has(type):
			var group := _tree.create_item(_tree.get_root(), _group_index(type, types))
			group.set_selectable(0, false)
			group.collapsed = true
			_groups[type] = group
		(_groups[type] as TreeItem).set_text(0, "%s  (%d)" % [type, counts[type]])
	for id in wanted:
		var entry: Dictionary = wanted[id]
		var row: TreeItem = _rows.get(id)
		if row == null:
			row = _tree.create_item(_groups[entry["type"]])
			row.set_metadata(0, id)
			_rows[id] = row
		row.set_text(0, "%s   #%d" % [entry["name"], id])

	_summary.text = "%d of %d shown" % [wanted.size(), _entries.size()] if not query.is_empty() \
		else "%d entities in %d types" % [wanted.size(), types.size()]
	# Expand everything while searching, so matches are visible.
	if not query.is_empty():
		for group in _groups.values():
			(group as TreeItem).collapsed = false

## Position for a new group so the types stay sorted.
func _group_index(type: String, sorted_types: Array) -> int:
	var index := 0
	for other in sorted_types:
		if other == type:
			return index
		if _groups.has(other):
			index += 1
	return -1
