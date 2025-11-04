extends BaseModel
class_name CitysModel

var name: String
var county : String
var level : int

func _init(_name: String = "", _county: String = "", _level: int = 1) -> void:
	super._init()
	self.name = _name
	self.county = _county
	self.level = _level
