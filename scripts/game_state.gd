extends Node

## Autoload: world layout, manual wood chops, stump regrow, territory expansion, save/load.

signal world_changed

#region Balance (step 1 — tweak here)
## Base wood per manual chop before multiplier (machine chops can use base × 1.0 later).
const WOOD_PER_CHOP_BASE := 2.0
## Manual chopping bonus vs future automation.
const MANUAL_WOOD_MULT := 2.5
## Seconds until a stump becomes a harvestable tree again.
const TREE_REGROW_SEC := 24.0
## Tiny idle drip so the bar moves between chops; keep small vs chop income.
const HOME_PASSIVE_WOOD_PER_SEC := 0.05
## Wood cost for the first territory expansion (~20 manual chops at default chop math).
const EXPANSION_WOOD_COST := 100.0
## Stone per click on a quarry tile (machines can use different rates later).
const STONE_PER_MANUAL_GATHER := 1.0
## Per-quarry-tile cooldown so manual mining stays tame.
const QUARRY_COOLDOWN_SEC := 2.0
## First crafted material from wood.
const PLANKS_PER_CRAFT := 1.0
const PLANK_WOOD_COST := 8.0
## Second recipe: kits used to place early shaft objects.
const SHAFT_KITS_PER_CRAFT := 1.0
const SHAFT_KIT_PLANK_COST := 2.0
const SHAFT_KIT_STONE_COST := 1.0
## Automation chain: wheel on river -> powered shaft network -> harvester on grass.
const WHEEL_KITS_PER_CRAFT := 1.0
const WHEEL_KIT_PLANK_COST := 3.0
const WHEEL_KIT_STONE_COST := 2.0
const HARVESTER_KITS_PER_CRAFT := 1.0
const HARVESTER_KIT_PLANK_COST := 4.0
const HARVESTER_KIT_STONE_COST := 3.0
const HARVESTER_WOOD_PER_SEC := 0.8
const HARVESTER_STONE_PER_SEC := 0.55
const POWER_PER_WHEEL := 1.0
const POWER_PER_HARVESTER := 1.0
const MACHINE_UPGRADE_RATE_BONUS := 0.25
const MACHINE_UPGRADE_PLANK_BASE := 8.0
const MACHINE_UPGRADE_STONE_BASE := 6.0
const MACHINE_UPGRADE_COST_SCALE := 1.6
const FACTORY_KITS_PER_CRAFT := 1.0
const FACTORY_KIT_PLANK_COST := 10.0
const FACTORY_KIT_STONE_COST := 8.0
const FACTORY_WOOD_CONSUME_PER_SEC := 1.2
const FACTORY_PLANKS_PER_SEC := 0.4
const STORAGE_KITS_PER_CRAFT := 1.0
const STORAGE_KIT_PLANK_COST := 6.0
const STORAGE_KIT_STONE_COST := 4.0
const STORAGE_WOOD_CAPACITY := 60.0
const CONVEYOR_KITS_PER_CRAFT := 2.0
const CONVEYOR_KIT_PLANK_COST := 2.0
const CONVEYOR_KIT_STONE_COST := 1.0
const WHEEL_UPGRADE_POWER_BONUS := 0.25
const FACTORY_UPGRADE_RATE_BONUS := 0.25
const WHEEL_UPGRADE_PLANK_BASE := 10.0
const WHEEL_UPGRADE_STONE_BASE := 10.0
const FACTORY_UPGRADE_PLANK_BASE := 12.0
const FACTORY_UPGRADE_STONE_BASE := 12.0
const UPGRADE_COST_SCALE := 1.7
const PLACEMENT_SUBDIV := 4
#endregion

const SAVE_PATH := "user://save.json"
## Bumped when save fields change. Loader still accepts older `v` when migrated below.
const SAVE_VERSION := 10

var world_map: WorldMap
var territory_expanded := false

## Vector2i -> seconds remaining until TREE returns.
var _tree_regrow: Dictionary = {}
## Vector2i -> seconds until this quarry tile can be mined again.
var _quarry_cooldown: Dictionary = {}

var wood := 0.0
var stone := 0.0
var planks := 0.0
var shaft_kits := 0.0
var wheel_kits := 0.0
var harvester_kits := 0.0
var factory_kits := 0.0
var storage_kits := 0.0
var conveyor_kits := 0.0
var machine_upgrade_level := 0
var wheel_upgrade_level := 0
var factory_upgrade_level := 0
var logistics_wood := 0.0
var _last_auto_planks_per_sec := 0.0

var shaft_place_mode := false
var wheel_place_mode := false
var harvester_place_mode := false
var factory_place_mode := false
var storage_place_mode := false
var conveyor_place_mode := false
## Vector2i -> true, for placed shafts.
var _placed_shafts: Dictionary = {}
var _placed_wheels: Dictionary = {}
var _placed_harvesters: Dictionary = {}
## Anchor sub-cell -> Array[Vector2i] occupied by this 1x2 harvester.
var _harvester_shapes: Dictionary = {}
## Sub-cell -> harvester anchor for fast occupancy checks.
var _harvester_subcell_owner: Dictionary = {}
var _placed_factories: Dictionary = {}
var _placed_storages: Dictionary = {}
var _placed_conveyors: Dictionary = {}
## Vector2i -> String ("wood" | "stone")
var _harvester_roles: Dictionary = {}
var _network_cache_dirty := true
var _power_reachable_nodes: Dictionary = {}
var _storage_reachable_nodes: Dictionary = {}
var _active_harvesters: Dictionary = {}
var _connected_factories: Dictionary = {}


func _ready() -> void:
	if not load_from_disk():
		_reset_run()
	_mark_network_cache_dirty()
	_ensure_network_cache()
	world_changed.emit()


func _exit_tree() -> void:
	save_to_disk()


func _process(delta: float) -> void:
	_last_auto_planks_per_sec = 0.0
	_ensure_network_cache()
	wood += HOME_PASSIVE_WOOD_PER_SEC * delta
	var done: Array[Vector2i] = []
	for c: Vector2i in _tree_regrow.keys():
		_tree_regrow[c] -= delta
		if _tree_regrow[c] <= 0.0:
			done.append(c)
	for c in done:
		_tree_regrow.erase(c)
		world_map.set_cell(c, WorldMap.Cell.TREE)
	if not done.is_empty():
		world_changed.emit()
	var q_done: Array[Vector2i] = []
	for c: Vector2i in _quarry_cooldown.keys():
		_quarry_cooldown[c] -= delta
		if _quarry_cooldown[c] <= 0.0:
			q_done.append(c)
	for c in q_done:
		_quarry_cooldown.erase(c)
	var rate_mul := get_machine_rate_multiplier()
	var power_eff := get_power_efficiency_multiplier()
	var produced_logistics_wood := 0.0
	for c: Vector2i in _placed_harvesters.keys():
		if is_harvester_active(c):
			var role := get_harvester_role(c)
			if role == "wood":
				produced_logistics_wood += HARVESTER_WOOD_PER_SEC * rate_mul * power_eff * delta
			elif role == "stone":
				stone += HARVESTER_STONE_PER_SEC * rate_mul * power_eff * delta
	if produced_logistics_wood > 0.0:
		logistics_wood += produced_logistics_wood
		wood += produced_logistics_wood
	var storage_cap := get_storage_capacity()
	if logistics_wood > storage_cap:
		logistics_wood = storage_cap
	var active_factory_count := get_connected_factory_count()
	var plank_target := float(active_factory_count) * FACTORY_PLANKS_PER_SEC * get_factory_rate_multiplier() * delta
	if plank_target > 0.0 and logistics_wood > 0.0:
		var wood_per_plank := get_factory_wood_per_plank()
		var max_planks_from_wood := logistics_wood / wood_per_plank if wood_per_plank > 0.0 else 0.0
		var produced := minf(plank_target, max_planks_from_wood)
		if produced > 0.0 and wood_per_plank > 0.0:
			var consumed_wood := produced * wood_per_plank
			logistics_wood -= consumed_wood
			wood = maxf(0.0, wood - consumed_wood)
			planks += produced
			if delta > 0.0:
				_last_auto_planks_per_sec = produced / delta


func try_chop_tree(cell: Vector2i) -> void:
	if _tree_regrow.has(cell):
		return
	var kind := world_map.cell_at(cell)
	if kind != WorldMap.Cell.TREE:
		return
	var gain := WOOD_PER_CHOP_BASE * MANUAL_WOOD_MULT
	wood += gain
	world_map.set_cell(cell, WorldMap.Cell.STUMP)
	_tree_regrow[cell] = TREE_REGROW_SEC
	world_changed.emit()
	save_to_disk()


func can_expand_territory() -> bool:
	return not territory_expanded and wood >= EXPANSION_WOOD_COST


func try_expand_territory() -> bool:
	if territory_expanded or wood < EXPANSION_WOOD_COST:
		return false
	wood -= EXPANSION_WOOD_COST
	world_map = WorldMap.expanded(world_map)
	territory_expanded = true
	world_changed.emit()
	save_to_disk()
	return true


func try_mine_quarry(cell: Vector2i) -> void:
	if _quarry_cooldown.get(cell, 0.0) > 0.0:
		return
	if world_map.cell_at(cell) != WorldMap.Cell.QUARRY:
		return
	stone += STONE_PER_MANUAL_GATHER
	_quarry_cooldown[cell] = QUARRY_COOLDOWN_SEC
	world_changed.emit()
	save_to_disk()


func can_craft_planks() -> bool:
	return wood >= PLANK_WOOD_COST


func craft_planks() -> bool:
	if not can_craft_planks():
		return false
	wood -= PLANK_WOOD_COST
	planks += PLANKS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_shaft_kit() -> bool:
	return planks >= SHAFT_KIT_PLANK_COST and stone >= SHAFT_KIT_STONE_COST


func craft_shaft_kit() -> bool:
	if not can_craft_shaft_kit():
		return false
	planks -= SHAFT_KIT_PLANK_COST
	stone -= SHAFT_KIT_STONE_COST
	shaft_kits += SHAFT_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_wheel_kit() -> bool:
	return planks >= WHEEL_KIT_PLANK_COST and stone >= WHEEL_KIT_STONE_COST


func craft_wheel_kit() -> bool:
	if not can_craft_wheel_kit():
		return false
	planks -= WHEEL_KIT_PLANK_COST
	stone -= WHEEL_KIT_STONE_COST
	wheel_kits += WHEEL_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_harvester_kit() -> bool:
	return planks >= HARVESTER_KIT_PLANK_COST and stone >= HARVESTER_KIT_STONE_COST


func craft_harvester_kit() -> bool:
	if not can_craft_harvester_kit():
		return false
	planks -= HARVESTER_KIT_PLANK_COST
	stone -= HARVESTER_KIT_STONE_COST
	harvester_kits += HARVESTER_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_factory_kit() -> bool:
	return planks >= FACTORY_KIT_PLANK_COST and stone >= FACTORY_KIT_STONE_COST


func craft_factory_kit() -> bool:
	if not can_craft_factory_kit():
		return false
	planks -= FACTORY_KIT_PLANK_COST
	stone -= FACTORY_KIT_STONE_COST
	factory_kits += FACTORY_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_storage_kit() -> bool:
	return planks >= STORAGE_KIT_PLANK_COST and stone >= STORAGE_KIT_STONE_COST


func craft_storage_kit() -> bool:
	if not can_craft_storage_kit():
		return false
	planks -= STORAGE_KIT_PLANK_COST
	stone -= STORAGE_KIT_STONE_COST
	storage_kits += STORAGE_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func can_craft_conveyor_kit() -> bool:
	return planks >= CONVEYOR_KIT_PLANK_COST and stone >= CONVEYOR_KIT_STONE_COST


func craft_conveyor_kit() -> bool:
	if not can_craft_conveyor_kit():
		return false
	planks -= CONVEYOR_KIT_PLANK_COST
	stone -= CONVEYOR_KIT_STONE_COST
	conveyor_kits += CONVEYOR_KITS_PER_CRAFT
	world_changed.emit()
	save_to_disk()
	return true


func get_machine_rate_multiplier() -> float:
	return 1.0 + MACHINE_UPGRADE_RATE_BONUS * float(machine_upgrade_level)


func get_wheel_power_multiplier() -> float:
	return 1.0 + WHEEL_UPGRADE_POWER_BONUS * float(wheel_upgrade_level)


func get_factory_rate_multiplier() -> float:
	return 1.0 + FACTORY_UPGRADE_RATE_BONUS * float(factory_upgrade_level)


func get_machine_upgrade_cost_planks() -> float:
	return MACHINE_UPGRADE_PLANK_BASE * pow(MACHINE_UPGRADE_COST_SCALE, machine_upgrade_level)


func get_machine_upgrade_cost_stone() -> float:
	return MACHINE_UPGRADE_STONE_BASE * pow(MACHINE_UPGRADE_COST_SCALE, machine_upgrade_level)


func can_buy_machine_upgrade() -> bool:
	return planks >= get_machine_upgrade_cost_planks() and stone >= get_machine_upgrade_cost_stone()


func buy_machine_upgrade() -> bool:
	if not can_buy_machine_upgrade():
		return false
	planks -= get_machine_upgrade_cost_planks()
	stone -= get_machine_upgrade_cost_stone()
	machine_upgrade_level += 1
	world_changed.emit()
	save_to_disk()
	return true


func get_wheel_upgrade_cost_planks() -> float:
	return WHEEL_UPGRADE_PLANK_BASE * pow(UPGRADE_COST_SCALE, wheel_upgrade_level)


func get_wheel_upgrade_cost_stone() -> float:
	return WHEEL_UPGRADE_STONE_BASE * pow(UPGRADE_COST_SCALE, wheel_upgrade_level)


func can_buy_wheel_upgrade() -> bool:
	return planks >= get_wheel_upgrade_cost_planks() and stone >= get_wheel_upgrade_cost_stone()


func buy_wheel_upgrade() -> bool:
	if not can_buy_wheel_upgrade():
		return false
	planks -= get_wheel_upgrade_cost_planks()
	stone -= get_wheel_upgrade_cost_stone()
	wheel_upgrade_level += 1
	world_changed.emit()
	save_to_disk()
	return true


func get_factory_upgrade_cost_planks() -> float:
	return FACTORY_UPGRADE_PLANK_BASE * pow(UPGRADE_COST_SCALE, factory_upgrade_level)


func get_factory_upgrade_cost_stone() -> float:
	return FACTORY_UPGRADE_STONE_BASE * pow(UPGRADE_COST_SCALE, factory_upgrade_level)


func can_buy_factory_upgrade() -> bool:
	return planks >= get_factory_upgrade_cost_planks() and stone >= get_factory_upgrade_cost_stone()


func buy_factory_upgrade() -> bool:
	if not can_buy_factory_upgrade():
		return false
	planks -= get_factory_upgrade_cost_planks()
	stone -= get_factory_upgrade_cost_stone()
	factory_upgrade_level += 1
	world_changed.emit()
	save_to_disk()
	return true


func set_place_mode(mode: String) -> void:
	var next_shaft := mode == "shaft"
	var next_wheel := mode == "wheel"
	var next_harvester := mode == "harvester"
	var next_factory := mode == "factory"
	var next_storage := mode == "storage"
	var next_conveyor := mode == "conveyor"
	if shaft_place_mode == next_shaft and wheel_place_mode == next_wheel and harvester_place_mode == next_harvester and factory_place_mode == next_factory and storage_place_mode == next_storage and conveyor_place_mode == next_conveyor:
		return
	shaft_place_mode = next_shaft
	wheel_place_mode = next_wheel
	harvester_place_mode = next_harvester
	factory_place_mode = next_factory
	storage_place_mode = next_storage
	conveyor_place_mode = next_conveyor
	world_changed.emit()


func get_placed_shafts() -> Dictionary:
	return _placed_shafts


func get_placed_wheels() -> Dictionary:
	return _placed_wheels


func get_placed_harvesters() -> Dictionary:
	return _placed_harvesters


func get_harvester_shapes() -> Dictionary:
	return _harvester_shapes


func get_placed_factories() -> Dictionary:
	return _placed_factories


func get_placed_storages() -> Dictionary:
	return _placed_storages


func get_placed_conveyors() -> Dictionary:
	return _placed_conveyors


func get_powered_shafts() -> Dictionary:
	return _build_powered_shafts_set()


func get_quarry_cooldown_ratio(cell: Vector2i) -> float:
	var remaining := float(_quarry_cooldown.get(cell, 0.0))
	if remaining <= 0.0:
		return 0.0
	return clampf(remaining / QUARRY_COOLDOWN_SEC, 0.0, 1.0)


func get_harvester_role(cell: Vector2i) -> String:
	return str(_harvester_roles.get(cell, "wood"))


func is_harvester_active(cell: Vector2i) -> bool:
	_ensure_network_cache()
	return _active_harvesters.has(cell)


func get_powered_harvester_count() -> int:
	var count := 0
	for c: Vector2i in _placed_harvesters.keys():
		if is_harvester_active(c):
			count += 1
	return count


func get_auto_wood_per_sec() -> float:
	var rate_mul := get_machine_rate_multiplier()
	var power_eff := get_power_efficiency_multiplier()
	var rate := 0.0
	for c: Vector2i in _placed_harvesters.keys():
		if is_harvester_active(c) and get_harvester_role(c) == "wood":
			rate += HARVESTER_WOOD_PER_SEC * rate_mul * power_eff
	return rate


func get_auto_stone_per_sec() -> float:
	var rate_mul := get_machine_rate_multiplier()
	var power_eff := get_power_efficiency_multiplier()
	var rate := 0.0
	for c: Vector2i in _placed_harvesters.keys():
		if is_harvester_active(c) and get_harvester_role(c) == "stone":
			rate += HARVESTER_STONE_PER_SEC * rate_mul * power_eff
	return rate


func get_total_wood_per_sec() -> float:
	return HOME_PASSIVE_WOOD_PER_SEC + get_auto_wood_per_sec()


func get_total_stone_per_sec() -> float:
	return get_auto_stone_per_sec()


func get_auto_planks_per_sec() -> float:
	return _last_auto_planks_per_sec


func get_factory_input_satisfaction() -> float:
	# 1.0 means enough wood for full factory throughput this second.
	var target_planks_per_sec := float(get_connected_factory_count()) * FACTORY_PLANKS_PER_SEC * get_factory_rate_multiplier()
	if target_planks_per_sec <= 0.0:
		return 1.0
	var wood_needed_per_sec := target_planks_per_sec * FACTORY_WOOD_CONSUME_PER_SEC
	if wood_needed_per_sec <= 0.0:
		return 1.0
	return clampf(logistics_wood / wood_needed_per_sec, 0.0, 1.0)


func get_factory_wood_demand_per_sec() -> float:
	return float(get_connected_factory_count()) * FACTORY_WOOD_CONSUME_PER_SEC * get_factory_rate_multiplier()


func get_factory_wood_per_plank() -> float:
	if FACTORY_PLANKS_PER_SEC <= 0.0:
		return 1.0
	return FACTORY_WOOD_CONSUME_PER_SEC / FACTORY_PLANKS_PER_SEC


func get_wood_collection_per_sec() -> float:
	return HOME_PASSIVE_WOOD_PER_SEC + get_auto_wood_per_sec()


func get_wood_usage_per_sec() -> float:
	return get_factory_wood_demand_per_sec() * get_factory_input_satisfaction()


func get_net_wood_per_sec() -> float:
	return get_wood_collection_per_sec() - get_wood_usage_per_sec()


func get_storage_capacity() -> float:
	return float(_placed_storages.size()) * STORAGE_WOOD_CAPACITY


func get_power_generated_per_sec() -> float:
	return float(_placed_wheels.size()) * POWER_PER_WHEEL * get_wheel_power_multiplier()


func get_power_consumed_per_sec() -> float:
	return float(get_powered_harvester_count()) * POWER_PER_HARVESTER


func get_power_surplus_per_sec() -> float:
	return get_power_generated_per_sec() - get_power_consumed_per_sec()


func get_power_efficiency_multiplier() -> float:
	var consumed := get_power_consumed_per_sec()
	if consumed <= 0.0:
		return 1.0
	return clampf(get_power_generated_per_sec() / consumed, 0.0, 1.0)


func can_place_shaft(cell: Vector2i) -> bool:
	if shaft_kits < 1.0:
		return false
	if _placed_shafts.has(cell):
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	return world_map.cell_at(cell) == WorldMap.Cell.GRASS and not _is_solid_occupied(cell)


func try_place_shaft(cell: Vector2i) -> bool:
	if not can_place_shaft(cell):
		return false
	shaft_kits -= 1.0
	_placed_shafts[cell] = true
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func can_place_wheel(cell: Vector2i) -> bool:
	if wheel_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	return world_map.cell_at(cell) == WorldMap.Cell.RIVER and not _placed_wheels.has(cell)


func try_place_wheel(cell: Vector2i) -> bool:
	if not can_place_wheel(cell):
		return false
	wheel_kits -= 1.0
	_placed_wheels[cell] = true
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func can_place_harvester(cell: Vector2i) -> bool:
	if harvester_kits < 1.0:
		return false
	if not _is_valid_subcell(cell):
		return false
	var place := _get_harvester_placement(cell)
	if place.is_empty():
		return false
	var cells: Array = place.get("cells", [])
	for sub in cells:
		var sc: Vector2i = sub
		if _harvester_subcell_owner.has(sc):
			return false
		var tile := _subcell_to_tile(sc)
		if world_map.cell_at(tile) != WorldMap.Cell.GRASS or _is_tile_blocked_for_sub_placement(tile):
			return false
	return true


func can_place_factory(cell: Vector2i) -> bool:
	if factory_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	if world_map.cell_at(cell) != WorldMap.Cell.GRASS:
		return false
	return not _is_solid_occupied(cell)


func can_place_storage(cell: Vector2i) -> bool:
	if storage_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	if world_map.cell_at(cell) != WorldMap.Cell.GRASS:
		return false
	return not _is_solid_occupied(cell)


func can_place_conveyor(cell: Vector2i) -> bool:
	if conveyor_kits < 1.0:
		return false
	if not _is_valid_subcell(cell):
		return false
	var tile := _subcell_to_tile(cell)
	if world_map.cell_at(tile) != WorldMap.Cell.GRASS:
		return false
	if _is_tile_blocked_for_sub_placement(tile):
		return false
	return not _placed_conveyors.has(cell)


func try_place_factory(cell: Vector2i) -> bool:
	if not can_place_factory(cell):
		return false
	factory_kits -= 1.0
	_placed_factories[cell] = true
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func try_place_storage(cell: Vector2i) -> bool:
	if not can_place_storage(cell):
		return false
	storage_kits -= 1.0
	_placed_storages[cell] = true
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func try_place_conveyor(cell: Vector2i) -> bool:
	if not can_place_conveyor(cell):
		return false
	conveyor_kits -= 1.0
	_placed_conveyors[cell] = true
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func try_place_harvester(cell: Vector2i) -> bool:
	if not can_place_harvester(cell):
		return false
	var place := _get_harvester_placement(cell)
	if place.is_empty():
		return false
	harvester_kits -= 1.0
	_placed_harvesters[cell] = true
	_harvester_roles[cell] = str(place.get("role", "wood"))
	var cells: Array = place.get("cells", [])
	_harvester_shapes[cell] = cells
	for sub in cells:
		_harvester_subcell_owner[sub] = cell
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()
	return true


func can_pickup_shaft(cell: Vector2i) -> bool:
	return _placed_shafts.has(cell)


func try_pickup_shaft(cell: Vector2i) -> bool:
	if not can_pickup_shaft(cell):
		return false
	_placed_shafts.erase(cell)
	# Full refund for now; add loss/decay later if you want relocation to have a cost.
	shaft_kits += 1.0
	world_changed.emit()
	save_to_disk()
	return true


func try_pickup_placeable(cell: Vector2i, preferred: String = "") -> bool:
	if _harvester_subcell_owner.has(cell):
		var anchor: Vector2i = _harvester_subcell_owner[cell]
		var old_cells: Array = _harvester_shapes.get(anchor, [])
		for sub in old_cells:
			_harvester_subcell_owner.erase(sub)
		_placed_harvesters.erase(anchor)
		_harvester_shapes.erase(anchor)
		_harvester_roles.erase(anchor)
		harvester_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if preferred == "conveyor" and _placed_conveyors.has(cell):
		_placed_conveyors.erase(cell)
		conveyor_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if preferred == "shaft" and _placed_shafts.has(cell):
		_placed_shafts.erase(cell)
		shaft_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_shafts.has(cell):
		_placed_shafts.erase(cell)
		shaft_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_wheels.has(cell):
		_placed_wheels.erase(cell)
		wheel_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_harvesters.has(cell):
		var old_cells: Array = _harvester_shapes.get(cell, [])
		for sub in old_cells:
			_harvester_subcell_owner.erase(sub)
		_placed_harvesters.erase(cell)
		_harvester_shapes.erase(cell)
		_harvester_roles.erase(cell)
		harvester_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_factories.has(cell):
		_placed_factories.erase(cell)
		factory_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_storages.has(cell):
		_placed_storages.erase(cell)
		storage_kits += 1.0
		var cap := get_storage_capacity()
		if logistics_wood > cap:
			logistics_wood = cap
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_conveyors.has(cell):
		_placed_conveyors.erase(cell)
		conveyor_kits += 1.0
		_mark_network_cache_dirty()
		world_changed.emit()
		save_to_disk()
		return true
	return false


func save_to_disk() -> void:
	var regrow_arr: Array = []
	for c: Vector2i in _tree_regrow.keys():
		regrow_arr.append({"x": c.x, "y": c.y, "t": float(_tree_regrow[c])})
	var quarry_cd_arr: Array = []
	for c: Vector2i in _quarry_cooldown.keys():
		quarry_cd_arr.append({"x": c.x, "y": c.y, "t": float(_quarry_cooldown[c])})
	var shafts_arr: Array = []
	for c: Vector2i in _placed_shafts.keys():
		shafts_arr.append({"x": c.x, "y": c.y})
	var wheels_arr: Array = []
	for c: Vector2i in _placed_wheels.keys():
		wheels_arr.append({"x": c.x, "y": c.y})
	var harvesters_arr: Array = []
	for c: Vector2i in _placed_harvesters.keys():
		harvesters_arr.append({
			"x": c.x,
			"y": c.y,
			"role": get_harvester_role(c),
			"cells": _cells_to_array_from_array(_harvester_shapes.get(c, [c])),
		})
	var factories_arr: Array = []
	for c: Vector2i in _placed_factories.keys():
		factories_arr.append({"x": c.x, "y": c.y})
	var storages_arr := _cells_to_array(_placed_storages)
	var conveyors_arr := _cells_to_array(_placed_conveyors)
	var cells_arr: Array = []
	cells_arr.resize(world_map.cells.size())
	for i in world_map.cells.size():
		cells_arr[i] = int(world_map.cells[i])
	var data := {
		"v": SAVE_VERSION,
		"wood": wood,
		"stone": stone,
		"planks": planks,
		"shaft_kits": shaft_kits,
		"wheel_kits": wheel_kits,
		"harvester_kits": harvester_kits,
		"factory_kits": factory_kits,
		"storage_kits": storage_kits,
		"conveyor_kits": conveyor_kits,
		"machine_upgrade_level": machine_upgrade_level,
		"wheel_upgrade_level": wheel_upgrade_level,
		"factory_upgrade_level": factory_upgrade_level,
		"logistics_wood": logistics_wood,
		"territory_expanded": territory_expanded,
		"map_w": world_map.width,
		"map_h": world_map.height,
		"cells": cells_arr,
		"regrow": regrow_arr,
		"quarry_cd": quarry_cd_arr,
		"shafts": shafts_arr,
		"wheels": wheels_arr,
		"harvesters": harvesters_arr,
		"factories": factories_arr,
		"storages": storages_arr,
		"conveyors": conveyors_arr,
	}
	var json := JSON.stringify(data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameState: could not open save path for write: %s" % SAVE_PATH)
		return
	file.store_string(json)


func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("GameState: save file not a JSON object")
		return false
	var d: Dictionary = data
	var ver := int(d.get("v", 0))
	if ver < 1 or ver > SAVE_VERSION:
		push_warning("GameState: save version unsupported (got %s)" % str(d.get("v")))
		return false
	var mw := int(d.get("map_w", 0))
	var mh := int(d.get("map_h", 0))
	var cells_raw = d.get("cells", [])
	if mw <= 0 or mh <= 0 or typeof(cells_raw) != TYPE_ARRAY:
		return false
	var need := mw * mh
	if cells_raw.size() != need:
		push_warning("GameState: cell count mismatch")
		return false
	var buf := PackedInt32Array()
	buf.resize(need)
	for i in need:
		buf[i] = int(cells_raw[i])
	world_map = WorldMap.new(mw, mh, buf)
	wood = float(d.get("wood", 0.0))
	stone = float(d.get("stone", 0.0))
	planks = float(d.get("planks", 0.0))
	shaft_kits = float(d.get("shaft_kits", 0.0))
	wheel_kits = float(d.get("wheel_kits", 0.0))
	harvester_kits = float(d.get("harvester_kits", 0.0))
	factory_kits = float(d.get("factory_kits", 0.0))
	storage_kits = float(d.get("storage_kits", 0.0))
	conveyor_kits = float(d.get("conveyor_kits", 0.0))
	machine_upgrade_level = int(d.get("machine_upgrade_level", 0))
	wheel_upgrade_level = int(d.get("wheel_upgrade_level", 0))
	factory_upgrade_level = int(d.get("factory_upgrade_level", 0))
	logistics_wood = float(d.get("logistics_wood", 0.0))
	territory_expanded = bool(d.get("territory_expanded", false))
	shaft_place_mode = false
	wheel_place_mode = false
	harvester_place_mode = false
	factory_place_mode = false
	storage_place_mode = false
	conveyor_place_mode = false
	_tree_regrow.clear()
	var reg_raw = d.get("regrow", [])
	if typeof(reg_raw) == TYPE_ARRAY:
		for item in reg_raw:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var rd: Dictionary = item
			var cx := int(rd.get("x", 0))
			var cy := int(rd.get("y", 0))
			var t := float(rd.get("t", 0.0))
			if t > 0.0:
				_tree_regrow[Vector2i(cx, cy)] = t
	_quarry_cooldown.clear()
	if ver >= 2:
		var q_raw = d.get("quarry_cd", [])
		if typeof(q_raw) == TYPE_ARRAY:
			for item in q_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var qd: Dictionary = item
				var qx := int(qd.get("x", 0))
				var qy := int(qd.get("y", 0))
				var qt := float(qd.get("t", 0.0))
				if qt > 0.0:
					_quarry_cooldown[Vector2i(qx, qy)] = qt
	_placed_shafts.clear()
	if ver >= 4:
		var shafts_raw = d.get("shafts", [])
		if typeof(shafts_raw) == TYPE_ARRAY:
			for item in shafts_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var sd: Dictionary = item
				var sx := int(sd.get("x", -1))
				var sy := int(sd.get("y", -1))
				var cell := Vector2i(sx, sy)
				if sx >= 0 and sy >= 0 and sx < world_map.width and sy < world_map.height:
					_placed_shafts[cell] = true
	_placed_wheels.clear()
	if ver >= 5:
		var wheels_raw = d.get("wheels", [])
		if typeof(wheels_raw) == TYPE_ARRAY:
			for item in wheels_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var wd: Dictionary = item
				var wx := int(wd.get("x", -1))
				var wy := int(wd.get("y", -1))
				if wx >= 0 and wy >= 0 and wx < world_map.width and wy < world_map.height:
					_placed_wheels[Vector2i(wx, wy)] = true
	_placed_harvesters.clear()
	_harvester_roles.clear()
	_harvester_shapes.clear()
	_harvester_subcell_owner.clear()
	if ver >= 5:
		var h_raw = d.get("harvesters", [])
		if typeof(h_raw) == TYPE_ARRAY:
			for item in h_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var hd: Dictionary = item
				var hx := int(hd.get("x", -1))
				var hy := int(hd.get("y", -1))
				var c := Vector2i(hx, hy)
				if ver < 10:
					if hx < 0 or hy < 0 or hx >= world_map.width or hy >= world_map.height:
						continue
					c = _tile_to_sub_origin(c) + Vector2i(1, 1)
				elif not _is_valid_subcell(c):
					continue
				_placed_harvesters[c] = true
				_harvester_roles[c] = str(hd.get("role", _pick_harvester_role(c)))
				var cells: Array = []
				if ver >= 10:
					cells = _array_to_cells_array(hd.get("cells", []))
				if cells.is_empty():
					cells = [c, c + Vector2i.RIGHT]
				_harvester_shapes[c] = cells
				for sub in cells:
					_harvester_subcell_owner[sub] = c
	_placed_factories.clear()
	_placed_storages.clear()
	_placed_conveyors.clear()
	if ver >= 7:
		var f_raw = d.get("factories", [])
		if typeof(f_raw) == TYPE_ARRAY:
			for item in f_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var fd: Dictionary = item
				var fx := int(fd.get("x", -1))
				var fy := int(fd.get("y", -1))
				if fx >= 0 and fy >= 0 and fx < world_map.width and fy < world_map.height:
					_placed_factories[Vector2i(fx, fy)] = true
	if ver >= 9:
		_array_to_tile_cells(d.get("storages", []), _placed_storages)
		_array_to_subcells(d.get("conveyors", []), _placed_conveyors)
	if ver < 3:
		planks = 0.0
	if ver < 4:
		shaft_kits = 0.0
	if ver < 5:
		wheel_kits = 0.0
		harvester_kits = 0.0
	if ver < 6:
		machine_upgrade_level = 0
	if ver < 7:
		factory_kits = 0.0
		wheel_upgrade_level = 0
		factory_upgrade_level = 0
	if ver < 9:
		storage_kits = 0.0
		conveyor_kits = 0.0
		logistics_wood = 0.0
	if logistics_wood > get_storage_capacity():
		logistics_wood = get_storage_capacity()
	_mark_network_cache_dirty()
	_ensure_network_cache()
	return true


func _reset_run() -> void:
	world_map = WorldMap.starter()
	territory_expanded = false
	_tree_regrow.clear()
	_quarry_cooldown.clear()
	wood = 0.0
	stone = 0.0
	planks = 0.0
	shaft_kits = 0.0
	wheel_kits = 0.0
	harvester_kits = 0.0
	factory_kits = 0.0
	storage_kits = 0.0
	conveyor_kits = 0.0
	machine_upgrade_level = 0
	wheel_upgrade_level = 0
	factory_upgrade_level = 0
	logistics_wood = 0.0
	shaft_place_mode = false
	wheel_place_mode = false
	harvester_place_mode = false
	factory_place_mode = false
	storage_place_mode = false
	conveyor_place_mode = false
	_placed_shafts.clear()
	_placed_wheels.clear()
	_placed_harvesters.clear()
	_placed_factories.clear()
	_placed_storages.clear()
	_placed_conveyors.clear()
	_harvester_roles.clear()
	_harvester_shapes.clear()
	_harvester_subcell_owner.clear()
	_mark_network_cache_dirty()


func dev_pickup_all_placeables() -> void:
	shaft_kits += float(_placed_shafts.size())
	wheel_kits += float(_placed_wheels.size())
	harvester_kits += float(_placed_harvesters.size())
	factory_kits += float(_placed_factories.size())
	storage_kits += float(_placed_storages.size())
	conveyor_kits += float(_placed_conveyors.size())
	_placed_shafts.clear()
	_placed_wheels.clear()
	_placed_harvesters.clear()
	_placed_factories.clear()
	_placed_storages.clear()
	_placed_conveyors.clear()
	_harvester_roles.clear()
	_harvester_shapes.clear()
	_harvester_subcell_owner.clear()
	_mark_network_cache_dirty()
	world_changed.emit()
	save_to_disk()


func _is_solid_occupied(cell: Vector2i) -> bool:
	if _placed_wheels.has(cell) or _placed_factories.has(cell) or _placed_storages.has(cell):
		return true
	var base := _tile_to_sub_origin(cell)
	for y in PLACEMENT_SUBDIV:
		for x in PLACEMENT_SUBDIV:
			if _harvester_subcell_owner.has(base + Vector2i(x, y)):
				return true
	return false


func _is_tile_blocked_for_sub_placement(tile: Vector2i) -> bool:
	return _placed_wheels.has(tile)


func _build_powered_shafts_set() -> Dictionary:
	var powered: Dictionary = {}
	var queue: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for wheel: Vector2i in _placed_wheels.keys():
		for dir: Vector2i in dirs:
			var n: Vector2i = wheel + dir
			if _placed_shafts.has(n) and not powered.has(n):
				powered[n] = true
				queue.append(n)
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		for dir: Vector2i in dirs:
			var n: Vector2i = cur + dir
			if _placed_shafts.has(n) and not powered.has(n):
				powered[n] = true
				queue.append(n)
	return powered


func _is_harvester_powered(cell: Vector2i, powered_shafts: Dictionary) -> bool:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir: Vector2i in dirs:
		if powered_shafts.has(cell + dir):
			return true
	return false


func _has_adjacent_resource(cell: Vector2i, resource_kind: int) -> bool:
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir: Vector2i in dirs:
		if world_map.cell_at(cell + dir) == resource_kind:
			return true
	return false


func get_harvester_candidate_cells() -> Dictionary:
	return {}


func get_harvester_candidate_roles() -> Dictionary:
	return {}


func get_harvester_preview_cells(anchor: Vector2i) -> Array:
	var place := _get_harvester_placement(anchor)
	if place.is_empty():
		return []
	return place.get("cells", [])


func _pick_harvester_role(cell: Vector2i) -> String:
	var tile := _subcell_to_tile(cell) if _is_valid_subcell(cell) else cell
	# If both resources are adjacent, prefer wood for early-game stability.
	if _has_adjacent_resource(tile, WorldMap.Cell.TREE):
		return "wood"
	if _has_adjacent_resource(tile, WorldMap.Cell.QUARRY):
		return "stone"
	return "wood"


func _cells_to_array(cells: Dictionary) -> Array:
	var out: Array = []
	for c: Vector2i in cells.keys():
		out.append({"x": c.x, "y": c.y})
	return out


func _cells_to_array_from_array(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		var cc: Vector2i = c
		out.append({"x": cc.x, "y": cc.y})
	return out


func _array_to_tile_cells(raw: Variant, out: Dictionary) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var x := int(d.get("x", -1))
		var y := int(d.get("y", -1))
		if x >= 0 and y >= 0 and x < world_map.width and y < world_map.height:
			out[Vector2i(x, y)] = true


func _array_to_subcells(raw: Variant, out: Dictionary) -> void:
	if typeof(raw) != TYPE_ARRAY:
		return
	var w := world_map.width * PLACEMENT_SUBDIV
	var h := world_map.height * PLACEMENT_SUBDIV
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var x := int(d.get("x", -1))
		var y := int(d.get("y", -1))
		if x >= 0 and y >= 0 and x < w and y < h:
			out[Vector2i(x, y)] = true


func _array_to_cells_array(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var x := int(d.get("x", -1))
		var y := int(d.get("y", -1))
		var c := Vector2i(x, y)
		if _is_valid_subcell(c):
			out.append(c)
	return out


func _is_logistics_node(cell: Vector2i) -> bool:
	return _placed_conveyors.has(cell) or _harvester_subcell_owner.has(cell)


func _is_machine_connected_to_power(start: Vector2i) -> bool:
	_ensure_network_cache()
	for s: Vector2i in _network_start_nodes_for_machine(start):
		if _power_reachable_nodes.has(s):
			return true
	return false


func _is_machine_connected_to_storage(start: Vector2i) -> bool:
	_ensure_network_cache()
	for s: Vector2i in _network_start_nodes_for_machine(start):
		if _storage_reachable_nodes.has(s):
			return true
	return false


func get_connected_factory_count() -> int:
	_ensure_network_cache()
	return _connected_factories.size()


func _is_valid_subcell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < world_map.width * PLACEMENT_SUBDIV and cell.y < world_map.height * PLACEMENT_SUBDIV


func _subcell_to_tile(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / PLACEMENT_SUBDIV, cell.y / PLACEMENT_SUBDIV)


func _tile_to_sub_origin(tile: Vector2i) -> Vector2i:
	return Vector2i(tile.x * PLACEMENT_SUBDIV, tile.y * PLACEMENT_SUBDIV)


func _target_subcells_for_tiles(tiles: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tile: Vector2i in tiles.keys():
		var base := _tile_to_sub_origin(tile)
		for i in PLACEMENT_SUBDIV:
			var left := Vector2i(base.x - 1, base.y + i)
			var right := Vector2i(base.x + PLACEMENT_SUBDIV, base.y + i)
			var up := Vector2i(base.x + i, base.y - 1)
			var down := Vector2i(base.x + i, base.y + PLACEMENT_SUBDIV)
			if _is_valid_subcell(left):
				out[left] = true
			if _is_valid_subcell(right):
				out[right] = true
			if _is_valid_subcell(up):
				out[up] = true
			if _is_valid_subcell(down):
				out[down] = true
	return out


func _network_start_nodes_for_machine(machine: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# Harvester anchors live directly on the sub-cell network.
	if _placed_harvesters.has(machine):
		var cells: Array = _harvester_shapes.get(machine, [])
		for c in cells:
			var sc: Vector2i = c
			if _is_logistics_node(sc):
				out.append(sc)
		return out
	# Building machines use neighboring sub-cells around their 4x4 footprint.
	var starts := _target_subcells_for_tiles({machine: true})
	for sc: Vector2i in starts.keys():
		if _is_logistics_node(sc):
			out.append(sc)
	return out


func _mark_network_cache_dirty() -> void:
	_network_cache_dirty = true


func _ensure_network_cache() -> void:
	if _network_cache_dirty:
		_rebuild_network_cache()


func _rebuild_network_cache() -> void:
	_power_reachable_nodes.clear()
	_storage_reachable_nodes.clear()
	_active_harvesters.clear()
	_connected_factories.clear()
	_network_cache_dirty = false
	var logistics_nodes: Dictionary = {}
	for c: Vector2i in _placed_conveyors.keys():
		logistics_nodes[c] = true
	for c: Vector2i in _harvester_subcell_owner.keys():
		logistics_nodes[c] = true
	if logistics_nodes.is_empty():
		return
	_power_reachable_nodes = _flood_reachable(logistics_nodes, _target_subcells_for_tiles(_placed_wheels))
	_storage_reachable_nodes = _flood_reachable(logistics_nodes, _target_subcells_for_tiles(_placed_storages))
	for h: Vector2i in _placed_harvesters.keys():
		var starts: Array[Vector2i] = _network_start_nodes_for_machine(h)
		for s: Vector2i in starts:
			if _power_reachable_nodes.has(s) and _storage_reachable_nodes.has(s):
				_active_harvesters[h] = true
				break
	for f: Vector2i in _placed_factories.keys():
		var starts_f: Array[Vector2i] = _network_start_nodes_for_machine(f)
		for s: Vector2i in starts_f:
			if _power_reachable_nodes.has(s) and _storage_reachable_nodes.has(s):
				_connected_factories[f] = true
				break


func _flood_reachable(logistics_nodes: Dictionary, sources: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var queue: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for s: Vector2i in sources.keys():
		if logistics_nodes.has(s) and not out.has(s):
			out[s] = true
			queue.append(s)
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		for dir: Vector2i in dirs:
			var n: Vector2i = cur + dir
			if not logistics_nodes.has(n) or out.has(n):
				continue
			out[n] = true
			queue.append(n)
	return out


func _get_harvester_placement(anchor: Vector2i) -> Dictionary:
	var tile := _subcell_to_tile(anchor)
	if world_map.cell_at(tile) != WorldMap.Cell.GRASS:
		return {}
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var best_role := ""
	var best_dir := Vector2i.ZERO
	for dir: Vector2i in dirs:
		var neighbor := tile + dir
		var kind := world_map.cell_at(neighbor)
		if kind == WorldMap.Cell.TREE:
			best_role = "wood"
			best_dir = dir
			break
		if kind == WorldMap.Cell.QUARRY and best_role == "":
			best_role = "stone"
			best_dir = dir
	if best_role == "":
		return {}
	var step := Vector2i(signi(best_dir.x), signi(best_dir.y))
	var cells: Array = [anchor, anchor + step]
	return {"role": best_role, "cells": cells}
