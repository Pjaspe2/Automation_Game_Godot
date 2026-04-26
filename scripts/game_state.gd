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
#endregion

const SAVE_PATH := "user://save.json"
## Bumped when save fields change. Loader still accepts older `v` when migrated below.
const SAVE_VERSION := 7

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
var machine_upgrade_level := 0

var shaft_place_mode := false
var wheel_place_mode := false
var harvester_place_mode := false
var factory_place_mode := false
## Vector2i -> true, for placed shafts.
var _placed_shafts: Dictionary = {}
var _placed_wheels: Dictionary = {}
var _placed_harvesters: Dictionary = {}
var _placed_factories: Dictionary = {}
## Vector2i -> String ("wood" | "stone")
var _harvester_roles: Dictionary = {}


func _ready() -> void:
	if not load_from_disk():
		_reset_run()
	world_changed.emit()


func _exit_tree() -> void:
	save_to_disk()


func _process(delta: float) -> void:
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
	var powered_shafts := _build_powered_shafts_set()
	var rate_mul := get_machine_rate_multiplier()
	for c: Vector2i in _placed_harvesters.keys():
		if _is_harvester_powered(c, powered_shafts):
			var role := get_harvester_role(c)
			if role == "wood":
				wood += HARVESTER_WOOD_PER_SEC * rate_mul * delta
			elif role == "stone":
				stone += HARVESTER_STONE_PER_SEC * rate_mul * delta
	var auto_planks := get_auto_planks_per_sec() * delta
	if auto_planks > 0.0:
		var max_planks_from_wood := wood / FACTORY_WOOD_CONSUME_PER_SEC if FACTORY_WOOD_CONSUME_PER_SEC > 0.0 else 0.0
		var produced := minf(auto_planks, max_planks_from_wood)
		if produced > 0.0:
			wood -= produced * FACTORY_WOOD_CONSUME_PER_SEC
			planks += produced


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


func get_machine_rate_multiplier() -> float:
	return 1.0 + MACHINE_UPGRADE_RATE_BONUS * float(machine_upgrade_level)


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


func set_place_mode(mode: String) -> void:
	var next_shaft := mode == "shaft"
	var next_wheel := mode == "wheel"
	var next_harvester := mode == "harvester"
	var next_factory := mode == "factory"
	if shaft_place_mode == next_shaft and wheel_place_mode == next_wheel and harvester_place_mode == next_harvester and factory_place_mode == next_factory:
		return
	shaft_place_mode = next_shaft
	wheel_place_mode = next_wheel
	harvester_place_mode = next_harvester
	factory_place_mode = next_factory
	world_changed.emit()


func get_placed_shafts() -> Dictionary:
	return _placed_shafts


func get_placed_wheels() -> Dictionary:
	return _placed_wheels


func get_placed_harvesters() -> Dictionary:
	return _placed_harvesters


func get_placed_factories() -> Dictionary:
	return _placed_factories


func get_powered_shafts() -> Dictionary:
	return _build_powered_shafts_set()


func get_quarry_cooldown_ratio(cell: Vector2i) -> float:
	var remaining := float(_quarry_cooldown.get(cell, 0.0))
	if remaining <= 0.0:
		return 0.0
	return clampf(remaining / QUARRY_COOLDOWN_SEC, 0.0, 1.0)


func get_harvester_role(cell: Vector2i) -> String:
	return str(_harvester_roles.get(cell, "wood"))


func get_powered_harvester_count() -> int:
	var powered_shafts := _build_powered_shafts_set()
	var count := 0
	for c: Vector2i in _placed_harvesters.keys():
		if _is_harvester_powered(c, powered_shafts):
			count += 1
	return count


func get_auto_wood_per_sec() -> float:
	var powered_shafts := _build_powered_shafts_set()
	var rate_mul := get_machine_rate_multiplier()
	var rate := 0.0
	for c: Vector2i in _placed_harvesters.keys():
		if _is_harvester_powered(c, powered_shafts) and get_harvester_role(c) == "wood":
			rate += HARVESTER_WOOD_PER_SEC * rate_mul
	return rate


func get_auto_stone_per_sec() -> float:
	var powered_shafts := _build_powered_shafts_set()
	var rate_mul := get_machine_rate_multiplier()
	var rate := 0.0
	for c: Vector2i in _placed_harvesters.keys():
		if _is_harvester_powered(c, powered_shafts) and get_harvester_role(c) == "stone":
			rate += HARVESTER_STONE_PER_SEC * rate_mul
	return rate


func get_total_wood_per_sec() -> float:
	return HOME_PASSIVE_WOOD_PER_SEC + get_auto_wood_per_sec()


func get_total_stone_per_sec() -> float:
	return get_auto_stone_per_sec()


func get_auto_planks_per_sec() -> float:
	return float(_placed_factories.size()) * FACTORY_PLANKS_PER_SEC * get_machine_rate_multiplier()


func get_factory_input_satisfaction() -> float:
	# 1.0 means enough wood for full factory throughput this second.
	var target_planks_per_sec := get_auto_planks_per_sec()
	if target_planks_per_sec <= 0.0:
		return 1.0
	var wood_needed_per_sec := target_planks_per_sec * FACTORY_WOOD_CONSUME_PER_SEC
	if wood_needed_per_sec <= 0.0:
		return 1.0
	return clampf(wood / wood_needed_per_sec, 0.0, 1.0)


func get_power_generated_per_sec() -> float:
	return float(_placed_wheels.size()) * POWER_PER_WHEEL


func get_power_consumed_per_sec() -> float:
	return float(get_powered_harvester_count()) * POWER_PER_HARVESTER


func get_power_surplus_per_sec() -> float:
	return get_power_generated_per_sec() - get_power_consumed_per_sec()


func can_place_shaft(cell: Vector2i) -> bool:
	if shaft_kits < 1.0:
		return false
	if _placed_shafts.has(cell):
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	return world_map.cell_at(cell) == WorldMap.Cell.GRASS and not _is_occupied(cell)


func try_place_shaft(cell: Vector2i) -> bool:
	if not can_place_shaft(cell):
		return false
	shaft_kits -= 1.0
	_placed_shafts[cell] = true
	world_changed.emit()
	save_to_disk()
	return true


func can_place_wheel(cell: Vector2i) -> bool:
	if wheel_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	return world_map.cell_at(cell) == WorldMap.Cell.RIVER and not _is_occupied(cell)


func try_place_wheel(cell: Vector2i) -> bool:
	if not can_place_wheel(cell):
		return false
	wheel_kits -= 1.0
	_placed_wheels[cell] = true
	world_changed.emit()
	save_to_disk()
	return true


func can_place_harvester(cell: Vector2i) -> bool:
	if harvester_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	if world_map.cell_at(cell) != WorldMap.Cell.GRASS or _is_occupied(cell):
		return false
	return _has_adjacent_resource(cell, WorldMap.Cell.TREE) or _has_adjacent_resource(cell, WorldMap.Cell.QUARRY)


func can_place_factory(cell: Vector2i) -> bool:
	if factory_kits < 1.0:
		return false
	if cell.x < 0 or cell.y < 0 or cell.x >= world_map.width or cell.y >= world_map.height:
		return false
	if world_map.cell_at(cell) != WorldMap.Cell.GRASS:
		return false
	return not _is_occupied(cell)


func try_place_factory(cell: Vector2i) -> bool:
	if not can_place_factory(cell):
		return false
	factory_kits -= 1.0
	_placed_factories[cell] = true
	world_changed.emit()
	save_to_disk()
	return true


func try_place_harvester(cell: Vector2i) -> bool:
	if not can_place_harvester(cell):
		return false
	harvester_kits -= 1.0
	_placed_harvesters[cell] = true
	_harvester_roles[cell] = _pick_harvester_role(cell)
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


func try_pickup_placeable(cell: Vector2i) -> bool:
	if _placed_shafts.has(cell):
		_placed_shafts.erase(cell)
		shaft_kits += 1.0
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_wheels.has(cell):
		_placed_wheels.erase(cell)
		wheel_kits += 1.0
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_harvesters.has(cell):
		_placed_harvesters.erase(cell)
		_harvester_roles.erase(cell)
		harvester_kits += 1.0
		world_changed.emit()
		save_to_disk()
		return true
	if _placed_factories.has(cell):
		_placed_factories.erase(cell)
		factory_kits += 1.0
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
		harvesters_arr.append({"x": c.x, "y": c.y, "role": get_harvester_role(c)})
	var factories_arr: Array = []
	for c: Vector2i in _placed_factories.keys():
		factories_arr.append({"x": c.x, "y": c.y})
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
		"machine_upgrade_level": machine_upgrade_level,
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
	machine_upgrade_level = int(d.get("machine_upgrade_level", 0))
	territory_expanded = bool(d.get("territory_expanded", false))
	shaft_place_mode = false
	wheel_place_mode = false
	harvester_place_mode = false
	factory_place_mode = false
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
	if ver >= 5:
		var h_raw = d.get("harvesters", [])
		if typeof(h_raw) == TYPE_ARRAY:
			for item in h_raw:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var hd: Dictionary = item
				var hx := int(hd.get("x", -1))
				var hy := int(hd.get("y", -1))
				if hx >= 0 and hy >= 0 and hx < world_map.width and hy < world_map.height:
					var c := Vector2i(hx, hy)
					_placed_harvesters[c] = true
					_harvester_roles[c] = str(hd.get("role", _pick_harvester_role(c)))
	_placed_factories.clear()
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
	machine_upgrade_level = 0
	shaft_place_mode = false
	wheel_place_mode = false
	harvester_place_mode = false
	factory_place_mode = false
	_placed_shafts.clear()
	_placed_wheels.clear()
	_placed_harvesters.clear()
	_placed_factories.clear()
	_harvester_roles.clear()


func _is_occupied(cell: Vector2i) -> bool:
	return _placed_shafts.has(cell) or _placed_wheels.has(cell) or _placed_harvesters.has(cell) or _placed_factories.has(cell)


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
	var out: Dictionary = {}
	for y in world_map.height:
		for x in world_map.width:
			var cell := Vector2i(x, y)
			if world_map.cell_at(cell) != WorldMap.Cell.GRASS:
				continue
			if _is_occupied(cell):
				continue
			if _has_adjacent_resource(cell, WorldMap.Cell.TREE) or _has_adjacent_resource(cell, WorldMap.Cell.QUARRY):
				out[cell] = true
	return out


func get_harvester_candidate_roles() -> Dictionary:
	var out: Dictionary = {}
	for c: Vector2i in get_harvester_candidate_cells().keys():
		out[c] = _pick_harvester_role(c)
	return out


func _pick_harvester_role(cell: Vector2i) -> String:
	# If both resources are adjacent, prefer wood for early-game stability.
	if _has_adjacent_resource(cell, WorldMap.Cell.TREE):
		return "wood"
	if _has_adjacent_resource(cell, WorldMap.Cell.QUARRY):
		return "stone"
	return "wood"
