class_name EcsWorldIndexSingleton
extends EcsSingleton

## What in the world is food, a crop, water, cover, a lure, a ready mate or a hunter: one
## shared lookup, kept by EcsWorldIndex.of() and read by the deciding systems. Tables hold
## component references, so live values (a crop's stock, a food's diet) need no rebuild.
## Dying entities are left out. Derived: never saved.

## Food on the ground: id -> EcsConsumableComponent.
var food: Dictionary = {}
## Food on the ground: id -> EcsPositionComponent.
var food_at: Dictionary = {}
## Harvestables: id -> EcsHarvestableComponent.
var crops: Dictionary = {}
## Harvestables: id -> EcsPositionComponent.
var crop_at: Dictionary = {}
## id -> EcsDrinkableComponent.
var water: Dictionary = {}
## id -> EcsCoverComponent.
var covers: Dictionary = {}
## Cover prey must visit (EcsHunting.is_lure): id -> EcsCoverComponent.
var lures: Dictionary = {}
## Diets some food or crop in the world serves: diet -> true.
var diets: Dictionary = {}
## Ready to breed: id -> its type_id.
var ready: Dictionary = {}
## Those that can hunt (EcsHunting.is_hunter): id -> true.
var hunters: Dictionary = {}

## The views each group was built from.
var food_view: EcsView
var crop_view: EcsView
var water_view: EcsView
var cover_view: EcsView
var ready_view: EcsView
var hunter_view: EcsView

func key() -> StringName:
	return &"world_index"
