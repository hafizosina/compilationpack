extends TileMapLayer

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame  # Wait extra frame for navigation
	apply_navigation_weights()

func apply_navigation_weights() -> void:
	# Get the navigation map from this layer
	var nav_map = get_navigation_map()
	if not nav_map.is_valid():
		print("Warning: No navigation map found")
		return
	
	# Get all navigation regions in this map
	var regions = NavigationServer2D.map_get_regions(nav_map)
	print("Found ", regions.size(), " navigation regions")
	
	var used_cells = get_used_cells()
	
	for cell in used_cells:
		var travel_cost = get_travel_cost_from_tile(cell)
		
		# Find the region RID for this cell position (using your working offset)
		var world_pos = map_to_local(cell)
		var region_rid = find_region_at_position(regions, world_pos)
		
		if region_rid.is_valid():
			NavigationServer2D.region_set_travel_cost(region_rid, travel_cost)

func get_travel_cost_from_tile(cell: Vector2i) -> float:
	var tile_data = get_cell_tile_data(cell)
	if not tile_data:
		print("Warning: No tile data for cell ", cell)
		return 1.0
	
	# Get the travel_cost from custom data that you set in tileset
	var travel_cost = tile_data.get_custom_data("travel_cost")
	if travel_cost == null:
		print("Warning: No travel_cost custom data for cell ", cell, " - using default 1.0")
		return 1.0
		
	return float(travel_cost)

func find_region_at_position(regions: Array, world_pos: Vector2) -> RID:
	# Simple approach - find region closest to the world position
	for region_rid in regions:
		var region_transform = NavigationServer2D.region_get_transform(region_rid)
		var region_pos = region_transform.origin
		
		# Check if this region is close to our target position
		if world_pos.distance_to(region_pos) < 32:  # Adjust threshold as needed
			return region_rid
	
	return RID()

# Update weights by re-reading from tileset custom data
func refresh_navigation_weights() -> void:
	apply_navigation_weights()
