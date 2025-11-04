class_name BaseModel
extends Resource

# Every record needs a unique ID (-1 means not saved yet)
var id: int = -1

# Reference to the database (set automatically when saved)
var _db: GraphDatabase

func _init() -> void:
	id = -1

# Convenience method: save this record to the database
func save() -> void:
	if _db:
		_db.save(self)

# Convenience method: delete this record from the database
func delete() -> void:
	if _db:
		_db.delete(self)
