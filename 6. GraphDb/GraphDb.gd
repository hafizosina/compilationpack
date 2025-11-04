# GraphDb.gd (Updated for Autoload)
class_name GraphDatabase
extends Node

static var instance: GraphDatabase

var _tables: Dictionary = {} # table_name -> Array[BaseModel]
var _relations: Dictionary = {} # Stores relationship metadata

func _ready() -> void:
	instance = self
	print("GraphDatabase initialized as singleton")

func _init() -> void:
	_tables = {}
	_relations = {}

# Register a model class
func register_model(model_class: GDScript, table_name: String) -> void:
	if not _tables.has(table_name):
		_tables[table_name] = {}

# Save or update a record
func save(record: BaseModel) -> BaseModel:
	var table_name = _get_table_name(record)
	
	if not _tables.has(table_name):
		_tables[table_name] = {}
	
	if record.id == -1:
		# New record
		record.id = ResourceUID.create_id()
	_tables[table_name].set(record.id,record)
	print("Created %s with ID %d" % [table_name, record.id])
	
	record._db = self
	return record

# Find by ID
func find(model_class: GDScript, record_id: int) -> BaseModel:
	var table_name = _get_table_name_from_class(model_class)
	if not _tables.has(table_name):
		return null
	
	return _tables[table_name].get(record_id)

# Find all records
func find_all(model_class: GDScript) -> Array:
	var table_name = _get_table_name_from_class(model_class)
	if not _tables.has(table_name):
		return []
	return _tables[table_name].values()

# Find with condition
func where(model_class: GDScript, condition: Callable) -> Array:
	var table_name = _get_table_name_from_class(model_class)
	if not _tables.has(table_name):
		return []
	
	var results = []
	for record in _tables[table_name].values():
		if condition.call(record):
			results.append(record)
	return results

# Delete a record
func delete(record: BaseModel) -> void:
	var table_name = _get_table_name(record)
	if not _tables.has(table_name):
		return
	
	var idx = _find_index(table_name, record.id)
	if idx != -1:
		_tables[table_name].remove_at(idx)
		_clear_relations(record)
		print("Deleted %s with ID %d" % [table_name, record.id])

# ONE-TO-ONE: Set relationship
func set_one_to_one(owner: BaseModel, related: BaseModel, rel_name: String) -> void:
	var key = _relation_key(owner, rel_name)
	if related == null:
		_relations.erase(key)
	else:
		_relations[key] = related.id

# ONE-TO-ONE: Get relationship
func get_one_to_one(owner: BaseModel, rel_name: String, model_class: GDScript) -> BaseModel:
	var key = _relation_key(owner, rel_name)
	if not _relations.has(key):
		return null
	
	var related_id = _relations[key]
	return find(model_class, related_id)

# ONE-TO-MANY: Add child
func add_one_to_many(parent: BaseModel, child: BaseModel, rel_name: String) -> void:
	var key = _relation_key(parent, rel_name)
	if not _relations.has(key):
		_relations[key] = []
	
	var children: Array = _relations[key]
	if not children.has(child.id):
		children.append(child.id)

# ONE-TO-MANY: Remove child
func remove_one_to_many(parent: BaseModel, child: BaseModel, rel_name: String) -> void:
	var key = _relation_key(parent, rel_name)
	if not _relations.has(key):
		return
	
	var children: Array = _relations[key]
	children.erase(child.id)

# ONE-TO-MANY: Get all children
func get_one_to_many(parent: BaseModel, rel_name: String, model_class: GDScript) -> Array:
	var key = _relation_key(parent, rel_name)
	if not _relations.has(key):
		return []
	
	var children_ids: Array = _relations[key]
	var results = []
	for child_id in children_ids:
		var child = find(model_class, child_id)
		if child:
			results.append(child)
	return results

# MANY-TO-MANY: Add relationship
func add_many_to_many(record_a: BaseModel, record_b: BaseModel, rel_name: String) -> void:
	var key = _relation_key(record_a, rel_name)
	if not _relations.has(key):
		_relations[key] = []
	
	var related: Array = _relations[key]
	if not related.has(record_b.id):
		related.append(record_b.id)

# MANY-TO-MANY: Remove relationship
func remove_many_to_many(record_a: BaseModel, record_b: BaseModel, rel_name: String) -> void:
	var key = _relation_key(record_a, rel_name)
	if not _relations.has(key):
		return
	
	var related: Array = _relations[key]
	related.erase(record_b.id)

# MANY-TO-MANY: Get all related
func get_many_to_many(record: BaseModel, rel_name: String, model_class: GDScript) -> Array:
	var key = _relation_key(record, rel_name)
	if not _relations.has(key):
		return []
	
	var related_ids: Array = _relations[key]
	var results = []
	for related_id in related_ids:
		var related_record = find(model_class, related_id)
		if related_record:
			results.append(related_record)
	return results

# Clear all data (useful for testing or reset)
func clear_all() -> void:
	_tables.clear()
	_relations.clear()
	print("Database cleared")

# Get database statistics
func get_stats() -> Dictionary:
	var stats = {}
	for table_name in _tables.keys():
		stats[table_name] = _tables[table_name].size()
	return stats

# Helper functions
func _get_table_name(record: BaseModel) -> String:
	return record.get_script().get_global_name()

func _get_table_name_from_class(model_class: GDScript) -> String:
	return model_class.get_global_name()

func _find_index(table_name: String, record_id: int) -> int:
	if not _tables.has(table_name):
		return -1
	
	for i in range(_tables[table_name].size()):
		if _tables[table_name][i].id == record_id:
			return i
	return -1

func _relation_key(record: BaseModel, rel_name: String) -> String:
	return "%s_%d_%s" % [_get_table_name(record), record.id, rel_name]

func _clear_relations(record: BaseModel) -> void:
	var table_name = _get_table_name(record)
	var prefix = "%s_%d_" % [table_name, record.id]
	
	var keys_to_remove = []
	for key in _relations.keys():
		if key.begins_with(prefix):
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		_relations.erase(key)
