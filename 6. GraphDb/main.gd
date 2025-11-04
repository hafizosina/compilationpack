extends Node2D
func _ready() -> void:
	var person1 = PersonModel.new("Alice", 30,2)
	GraphDb.save(person1)
	var person2 = PersonModel.new("Bob", 27,5)
	GraphDb.save(person2)
	var person3 = PersonModel.new("Cici", 40,5)
	GraphDb.save(person3)
	var person4 = PersonModel.new("Alex", 12,5)
	GraphDb.save(person4)
	
	var city1 = CitysModel.new("Padang", "Indonesia",2)
	GraphDb.save(city1)
	var city2 = CitysModel.new("Bukittinggi", "Indonesia",5)
	GraphDb.save(city2)
	
	
	GraphDb.add_one_to_many(city1, person1, "resident")
	GraphDb.add_one_to_many(city1, person2, "resident")
	GraphDb.add_one_to_many(city1, person3, "resident")
	GraphDb.add_one_to_many(city2, person4, "resident")
	
	
	GraphDb.add_many_to_many(person1, person2, "relation")

	# Query examples
	print("=== All Person ===")
	for person in GraphDb.find_all(PersonModel):
		print("User: ", person.name, " (", person.age, ")")
	
	print("\n=== City1's Resident (One-to-Many) ===")
	for person in GraphDb.get_one_to_many(city1, "resident", PersonModel):
		print("Person: ", person.name)
	
	# Get person2's relations (Many-to-Many reverse lookup)
	print("\n=== Person1's Relations ===")
	for person in GraphDb.get_many_to_many(person1, "relation", PersonModel):
		print("Related to: ", person.name)

	# Find specific people
	print("\n=== People aged bellow 27 ===")
	for person in GraphDb.where(PersonModel, func(p): return p.age < 27):
		print(person.name)

	# Remove a resident
	GraphDb.remove_one_to_many(city1, person2, "resident")
	print("\n=== After removing Bob from Padang ===")
	for person in GraphDb.get_one_to_many(city1, "resident", PersonModel):
		print("Person: ", person.name)
