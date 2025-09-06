extends TileMapLayer

@export var navigation_layer_mask: int = 1  # optional: only touch regions on these nav layers

func _ready() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	apply_navigation_weights()
	# Re-apply if tiles change at runtime
	changed.connect(apply_navigation_weights)

func apply_navigation_weights() -> void:
	var nav_map: RID = get_navigation_map()
	if not nav_map.is_valid():
		return

	var regions: Array = NavigationServer2D.map_get_regions(nav_map)
	if regions.is_empty():
		return

	for rid in regions:
		# If you use navigation layers, skip unrelated regions (optional)
		if navigation_layer_mask != 0:
			var layers := NavigationServer2D.region_get_navigation_layers(rid)
			if (layers & navigation_layer_mask) == 0:
				continue

		# Region transform origin is in global space; convert to this layer's local, then to a cell.
		var region_xform: Transform2D = NavigationServer2D.region_get_transform(rid)
		var local_pos: Vector2 = to_local(region_xform.origin)
		var cell: Vector2i = local_to_map(local_pos)

		var tile_data := get_cell_tile_data(cell)
		if tile_data == null:
			continue

		var cost :float= tile_data.get_custom_data("travel_cost")
		if cost == null:
			# no custom data on this tile; leave engine default
			continue

		NavigationServer2D.region_set_travel_cost(rid, float(cost))

func refresh_navigation_weights() -> void:
	apply_navigation_weights()
