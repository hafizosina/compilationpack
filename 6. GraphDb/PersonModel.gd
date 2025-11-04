extends BaseModel
class_name PersonModel

var name: String
var age: int
var level : int

func _init(_name: String = "", _age: int = 0, _level: int = 1) -> void:
	super._init()
	self.name = _name
	self.age = _age
	self.level = _level
