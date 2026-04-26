extends Control

## Renders `GameState.world_map` with Kenney Tiny Town tiles (`tilemap_packed.png`).

const BASE_MAP_SCALE := 2.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.2
const ZOOM_STEP := 1.15
const RIVER_COLOR := Color(0.20, 0.48, 0.90, 0.95)
const RIVER_CURRENT_COLOR := Color(0.92, 0.97, 1.0, 0.45)
const RIVER_CURRENT_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.75)
const QUARRY_COOLDOWN_SHADE := Color(0.22, 0.22, 0.22, 0.6)
const SHAFT_COLOR := Color(0.55, 0.36, 0.20, 0.95)
const SHAFT_BORDER_COLOR := Color(0.16, 0.10, 0.06, 1.0)
const POWERED_SHAFT_GLOW := Color(1.0, 0.95, 0.55, 0.35)
const WHEEL_COLOR := Color(0.35, 0.22, 0.08, 0.95)
const WHEEL_BORDER_COLOR := Color(0.12, 0.07, 0.03, 1.0)
const WHEEL_HIGHLIGHT_COLOR := Color(0.76, 0.58, 0.35, 0.95)
const FACTORY_COLOR := Color(0.58, 0.42, 0.22, 0.95)
const FACTORY_STARVED_COLOR := Color(0.34, 0.28, 0.24, 0.95)
const FACTORY_BORDER_COLOR := Color(0.18, 0.12, 0.06, 1.0)
const STORAGE_COLOR := Color(0.46, 0.30, 0.18, 0.95)
const STORAGE_BORDER_COLOR := Color(0.16, 0.10, 0.06, 1.0)
const CONVEYOR_COLOR := Color(0.03, 0.03, 0.03, 0.95)
const CONVEYOR_BORDER_COLOR := Color(0.22, 0.22, 0.22, 1.0)
const CONVEYOR_PULSE_COLOR := Color(0.65, 0.65, 0.65, 0.95)
const HARVESTER_BORDER_COLOR := Color(0.2, 0.2, 0.24, 1.0)
const HARVESTER_OFF_COLOR := Color(0.30, 0.72, 0.34, 0.95)
const HARVESTER_ON_COLOR := Color(0.27, 0.55, 0.95, 0.96)
const HELPER_WOOD_COLOR := Color(0.32, 0.88, 0.40, 0.25)
const HELPER_STONE_COLOR := Color(0.75, 0.80, 0.92, 0.25)
const GHOST_VALID_COLOR := Color(0.25, 0.95, 0.35, 0.38)
const GHOST_INVALID_COLOR := Color(0.95, 0.20, 0.20, 0.42)
const RIVER_FLOW_STEP_SEC := 0.16
const RIVER_FLOW_WAVELENGTH := 4
const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const TREE_COLOR := Color(0.12, 0.42, 0.16, 0.95)
const TREE_SHADE_COLOR := Color(0.08, 0.30, 0.11, 0.95)
const SUBGRID_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.08)

@onready var _layer: TileMapLayer = $TileMapLayer
@onready var _gs: Node = get_node("/root/GameState")

var _source_id: int = 0
var _hover_cell := Vector2i(-1, -1)
var _hover_subcell := Vector2i(-1, -1)
var _has_hover_cell := false
var _flow_tick := 0
var _flow_accum := 0.0
var _zoom := 1.0
var _drag_place_conveyor := false
var _conveyor_flow_dist: Dictionary = {}
var _conveyor_flow_cache_dirty := true


func _ready() -> void:
	_apply_zoom()
	# Keep tile sprites behind this Control's overlay draw calls (river/shaft/ghost markers).
	_layer.z_index = -1
	_build_tileset()
	mouse_exited.connect(_on_mouse_exited)
	_gs.world_changed.connect(_on_world_changed)
	_on_world_changed()


func _cell_display_px() -> float:
	return float(TinyTownAtlas.TILE_PX) * BASE_MAP_SCALE * _zoom


func _apply_zoom() -> void:
	var s := BASE_MAP_SCALE * _zoom
	_layer.scale = Vector2(s, s)
	_sync_size()
	queue_redraw()


func zoom_by_wheel_direction(is_zoom_in: bool) -> void:
	zoom_by_factor(ZOOM_STEP if is_zoom_in else 1.0 / ZOOM_STEP)


func zoom_by_factor(factor: float) -> void:
	if factor <= 0.0:
		return
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_apply_zoom()


func reset_zoom() -> void:
	_zoom = 1.0
	_apply_zoom()


func _try_place_conveyor_at_subcell(sub_cell: Vector2i) -> bool:
	if _gs.try_place_conveyor(sub_cell):
		accept_event()
		return true
	return false


func _build_tileset() -> void:
	var tex: Texture2D = load(TinyTownAtlas.TEXTURE_PATH) as Texture2D
	if tex == null:
		push_error("MapGridView: missing texture %s" % TinyTownAtlas.TEXTURE_PATH)
		return
	var ts := TileSet.new()
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TinyTownAtlas.TILE_PX, TinyTownAtlas.TILE_PX)
	# TileSetAtlasSource needs explicit tile definitions before set_cell can render them.
	var seen: Dictionary = {}
	for ac: Vector2i in TinyTownAtlas.ATLAS.values():
		if seen.has(ac):
			continue
		seen[ac] = true
		if not atlas.has_tile(ac):
			atlas.create_tile(ac)
	_source_id = ts.add_source(atlas)
	_layer.tile_set = ts


func _on_world_changed() -> void:
	_sync_size()
	_refresh_tiles()
	_conveyor_flow_cache_dirty = true
	queue_redraw()


func _process(delta: float) -> void:
	_flow_accum += delta
	while _flow_accum >= RIVER_FLOW_STEP_SEC:
		_flow_accum -= RIVER_FLOW_STEP_SEC
		_flow_tick += 1
		if _flow_tick > 1_000_000:
			_flow_tick = 0
		queue_redraw()


func _sync_size() -> void:
	var w: WorldMap = _gs.world_map as WorldMap
	var d := _cell_display_px()
	if w.width == 0:
		custom_minimum_size = Vector2(d * 4.0, d * 4.0)
		size = custom_minimum_size
		update_minimum_size()
		return
	custom_minimum_size = Vector2(w.width * d, w.height * d)
	size = custom_minimum_size
	update_minimum_size()


func _refresh_tiles() -> void:
	var w: WorldMap = _gs.world_map as WorldMap
	_layer.clear()
	if w.width == 0 or _layer.tile_set == null:
		return
	for y in w.height:
		for x in w.width:
			var kind: int = w.cells[y * w.width + x]
			if kind == WorldMap.Cell.RIVER or kind == WorldMap.Cell.TREE:
				# River is intentionally a flat color for readability.
				continue
			var ac := TinyTownAtlas.atlas_for_cell(kind)
			_layer.set_cell(Vector2i(x, y), _source_id, ac)


func _draw() -> void:
	var w: WorldMap = _gs.world_map as WorldMap
	if w.width == 0:
		return
	var d := _cell_display_px()
	var sub := d / float(_gs.PLACEMENT_SUBDIV)
	var view_rect := _get_visible_map_rect()
	if _gs.conveyor_place_mode or _gs.harvester_place_mode:
		for x in w.width * int(_gs.PLACEMENT_SUBDIV) + 1:
			var xx := float(x) * sub
			draw_line(Vector2(xx, 0.0), Vector2(xx, custom_minimum_size.y), SUBGRID_LINE_COLOR, 1.0)
		for y in w.height * int(_gs.PLACEMENT_SUBDIV) + 1:
			var yy := float(y) * sub
			draw_line(Vector2(0.0, yy), Vector2(custom_minimum_size.x, yy), SUBGRID_LINE_COLOR, 1.0)
	for y in w.height:
		for x in w.width:
			var kind: int = w.cells[y * w.width + x]
			if kind != WorldMap.Cell.RIVER:
				continue
			var rect := Rect2(x * d, y * d, d - 1.0, d - 1.0)
			draw_rect(rect, RIVER_COLOR)
			if _is_current_phase(x):
				var inset := d * 0.16
				var band := Rect2(rect.position.x + inset, rect.position.y + inset, rect.size.x - inset * 2.0, rect.size.y - inset * 2.0)
				draw_rect(band, RIVER_CURRENT_COLOR)
				var y_mid := band.position.y + band.size.y * 0.5
				draw_line(Vector2(band.position.x, y_mid), Vector2(band.position.x + band.size.x, y_mid), RIVER_CURRENT_LINE_COLOR, 2.0)
	for y in w.height:
		for x in w.width:
			if w.cells[y * w.width + x] != WorldMap.Cell.TREE:
				continue
			var rect := Rect2(x * d, y * d, d - 1.0, d - 1.0)
			draw_rect(rect, TREE_COLOR)
			var inner := Rect2(rect.position.x + d * 0.14, rect.position.y + d * 0.14, rect.size.x - d * 0.28, rect.size.y - d * 0.28)
			draw_rect(inner, TREE_SHADE_COLOR)
	for y in w.height:
		for x in w.width:
			if w.cells[y * w.width + x] != WorldMap.Cell.QUARRY:
				continue
			var cooldown_ratio: float = float(_gs.get_quarry_cooldown_ratio(Vector2i(x, y)))
			if cooldown_ratio <= 0.0:
				continue
			var shade := Color(QUARRY_COOLDOWN_SHADE.r, QUARRY_COOLDOWN_SHADE.g, QUARRY_COOLDOWN_SHADE.b, QUARRY_COOLDOWN_SHADE.a * cooldown_ratio)
			var rect := Rect2(x * d, y * d, d - 1.0, d - 1.0)
			draw_rect(rect, shade)
	var shafts: Dictionary = _gs.get_placed_shafts()
	var powered_shafts: Dictionary = _gs.get_powered_shafts()
	for c: Vector2i in shafts.keys():
		var center := Vector2(c.x * d + d * 0.5, c.y * d + d * 0.5)
		var half := d * 0.13
		var rect := Rect2(center.x - half, center.y - half, half * 2.0, half * 2.0)
		if not _is_rect_visible(rect, view_rect):
			continue
		var link := d * 0.11
		if shafts.has(c + Vector2i.UP):
			draw_rect(Rect2(center.x - link, c.y * d, link * 2.0, center.y - c.y * d), SHAFT_COLOR)
			draw_rect(Rect2(center.x - link, c.y * d, link * 2.0, center.y - c.y * d), SHAFT_BORDER_COLOR, false, 1.5)
		if shafts.has(c + Vector2i.DOWN):
			draw_rect(Rect2(center.x - link, center.y, link * 2.0, (c.y + 1) * d - center.y), SHAFT_COLOR)
			draw_rect(Rect2(center.x - link, center.y, link * 2.0, (c.y + 1) * d - center.y), SHAFT_BORDER_COLOR, false, 1.5)
		if shafts.has(c + Vector2i.LEFT):
			draw_rect(Rect2(c.x * d, center.y - link, center.x - c.x * d, link * 2.0), SHAFT_COLOR)
			draw_rect(Rect2(c.x * d, center.y - link, center.x - c.x * d, link * 2.0), SHAFT_BORDER_COLOR, false, 1.5)
		if shafts.has(c + Vector2i.RIGHT):
			draw_rect(Rect2(center.x, center.y - link, (c.x + 1) * d - center.x, link * 2.0), SHAFT_COLOR)
			draw_rect(Rect2(center.x, center.y - link, (c.x + 1) * d - center.x, link * 2.0), SHAFT_BORDER_COLOR, false, 1.5)
		if powered_shafts.has(c):
			var glow := Rect2(c.x * d + d * 0.08, c.y * d + d * 0.08, d - d * 0.16, d - d * 0.16)
			draw_rect(glow, POWERED_SHAFT_GLOW)
		draw_rect(rect, SHAFT_COLOR)
		draw_rect(rect, SHAFT_BORDER_COLOR, false, 2.0)
		draw_line(Vector2(rect.position.x + 2.0, center.y), Vector2(rect.position.x + rect.size.x - 2.0, center.y), SHAFT_BORDER_COLOR, 1.5)
	for c: Vector2i in _gs.get_placed_wheels().keys():
		var rect := Rect2(c.x * d + d * 0.18, c.y * d + d * 0.18, d * 0.64, d * 0.64)
		if not _is_rect_visible(rect, view_rect):
			continue
		draw_rect(rect, WHEEL_COLOR)
		draw_rect(rect, WHEEL_BORDER_COLOR, false, 2.0)
		var x_mid := rect.position.x + rect.size.x * 0.5
		var y_mid := rect.position.y + rect.size.y * 0.5
		var phase: int = int(posmod(_flow_tick + c.x + c.y, 4))
		var spoke_len := d * 0.20
		match phase:
			0:
				draw_line(Vector2(x_mid - spoke_len, y_mid), Vector2(x_mid + spoke_len, y_mid), WHEEL_HIGHLIGHT_COLOR, 2.0)
			1:
				draw_line(Vector2(x_mid - spoke_len * 0.7, y_mid - spoke_len * 0.7), Vector2(x_mid + spoke_len * 0.7, y_mid + spoke_len * 0.7), WHEEL_HIGHLIGHT_COLOR, 2.0)
			2:
				draw_line(Vector2(x_mid, y_mid - spoke_len), Vector2(x_mid, y_mid + spoke_len), WHEEL_HIGHLIGHT_COLOR, 2.0)
			_:
				draw_line(Vector2(x_mid - spoke_len * 0.7, y_mid + spoke_len * 0.7), Vector2(x_mid + spoke_len * 0.7, y_mid - spoke_len * 0.7), WHEEL_HIGHLIGHT_COLOR, 2.0)
		draw_line(Vector2(x_mid, rect.position.y + 2.0), Vector2(x_mid, rect.position.y + rect.size.y - 2.0), WHEEL_BORDER_COLOR, 2.0)
		draw_line(Vector2(rect.position.x + 2.0, y_mid), Vector2(rect.position.x + rect.size.x - 2.0, y_mid), WHEEL_BORDER_COLOR, 2.0)
	for c: Vector2i in _gs.get_placed_factories().keys():
		var rect := Rect2(c.x * d + d * 0.12, c.y * d + d * 0.12, d * 0.76, d * 0.76)
		if not _is_rect_visible(rect, view_rect):
			continue
		var fed: bool = float(_gs.get_factory_input_satisfaction()) >= 0.999
		draw_rect(rect, FACTORY_COLOR if fed else FACTORY_STARVED_COLOR)
		draw_rect(rect, FACTORY_BORDER_COLOR, false, 2.0)
		var roof := Rect2(rect.position.x + 3.0, rect.position.y + 3.0, rect.size.x - 6.0, rect.size.y * 0.4)
		draw_rect(roof, Color(0.72, 0.55, 0.32, 0.95))
		var smoke_x := rect.position.x + rect.size.x * 0.76
		if fed:
			draw_line(Vector2(smoke_x, rect.position.y + 4.0), Vector2(smoke_x, rect.position.y - 4.0), FACTORY_BORDER_COLOR, 2.0)
	for c: Vector2i in _gs.get_placed_storages().keys():
		var rect := Rect2(c.x * d + d * 0.14, c.y * d + d * 0.14, d * 0.72, d * 0.72)
		if not _is_rect_visible(rect, view_rect):
			continue
		draw_rect(rect, STORAGE_COLOR)
		draw_rect(rect, STORAGE_BORDER_COLOR, false, 2.0)
		var lid := Rect2(rect.position.x + 3.0, rect.position.y + 3.0, rect.size.x - 6.0, rect.size.y * 0.26)
		draw_rect(lid, Color(0.62, 0.44, 0.28, 0.95))
	var conveyors: Dictionary = _gs.get_placed_conveyors()
	_ensure_conveyor_flow_cache()
	var conveyor_dist: Dictionary = _conveyor_flow_dist
	for c: Vector2i in conveyors.keys():
		var center := Vector2((float(c.x) + 0.5) * sub, (float(c.y) + 0.5) * sub)
		var half := sub * 0.35
		var rect := Rect2(center.x - half, center.y - half, half * 2.0, half * 2.0)
		if not _is_rect_visible(rect, view_rect):
			continue
		var link := sub * 0.22
		if conveyors.has(c + Vector2i.UP):
			draw_rect(Rect2(center.x - link, float(c.y) * sub, link * 2.0, center.y - float(c.y) * sub), CONVEYOR_COLOR)
		if conveyors.has(c + Vector2i.DOWN):
			draw_rect(Rect2(center.x - link, center.y, link * 2.0, (float(c.y) + 1.0) * sub - center.y), CONVEYOR_COLOR)
		if conveyors.has(c + Vector2i.LEFT):
			draw_rect(Rect2(float(c.x) * sub, center.y - link, center.x - float(c.x) * sub, link * 2.0), CONVEYOR_COLOR)
		if conveyors.has(c + Vector2i.RIGHT):
			draw_rect(Rect2(center.x, center.y - link, (float(c.x) + 1.0) * sub - center.x, link * 2.0), CONVEYOR_COLOR)
		draw_rect(rect, CONVEYOR_COLOR)
		draw_rect(rect, CONVEYOR_BORDER_COLOR, false, 2.0)
		var phase: int = int(posmod(_flow_tick + c.x + c.y, 4))
		var pulse_w := rect.size.x * 0.26
		var pulse_t := float(phase) / 3.0
		var flow_dir := _get_conveyor_flow_dir(c, conveyors, conveyor_dist)
		var pulse := Rect2(rect.position.x + (rect.size.x - pulse_w) * pulse_t, rect.position.y + rect.size.y * 0.22, pulse_w, rect.size.y * 0.56)
		var has_h := conveyors.has(c + Vector2i.LEFT) or conveyors.has(c + Vector2i.RIGHT)
		var has_v := conveyors.has(c + Vector2i.UP) or conveyors.has(c + Vector2i.DOWN)
		if flow_dir == Vector2i.RIGHT:
			pulse = Rect2(float(c.x) * sub + (sub - pulse_w) * pulse_t, center.y - link, pulse_w, link * 2.0)
		elif flow_dir == Vector2i.LEFT:
			pulse = Rect2(float(c.x) * sub + (sub - pulse_w) * (1.0 - pulse_t), center.y - link, pulse_w, link * 2.0)
		elif flow_dir == Vector2i.DOWN:
			pulse = Rect2(center.x - link, float(c.y) * sub + (sub - pulse_w) * pulse_t, link * 2.0, pulse_w)
		elif flow_dir == Vector2i.UP:
			pulse = Rect2(center.x - link, float(c.y) * sub + (sub - pulse_w) * (1.0 - pulse_t), link * 2.0, pulse_w)
		elif has_h and not has_v:
			pulse = Rect2(c.x * d + (d - pulse_w) * pulse_t, center.y - link, pulse_w, link * 2.0)
		elif has_v and not has_h:
			pulse = Rect2(center.x - link, c.y * d + (d - pulse_w) * pulse_t, link * 2.0, pulse_w)
		draw_rect(pulse, CONVEYOR_PULSE_COLOR)
	for c: Vector2i in _gs.get_placed_harvesters().keys():
		var cells: Array = _gs.get_harvester_shapes().get(c, [c])
		var rect := _bounds_rect_for_subcells(cells, sub, sub * 0.08)
		if not _is_rect_visible(rect, view_rect):
			continue
		var active: bool = bool(_gs.is_harvester_active(c))
		draw_rect(rect, HARVESTER_ON_COLOR if active else HARVESTER_OFF_COLOR)
		draw_rect(rect, HARVESTER_BORDER_COLOR, false, 2.0)
		var pipe_y := rect.position.y + rect.size.y * 0.76
		draw_line(Vector2(rect.position.x + 4.0, pipe_y), Vector2(rect.position.x + rect.size.x - 4.0, pipe_y), HARVESTER_BORDER_COLOR, 2.0)
	if (_gs.shaft_place_mode or _gs.wheel_place_mode or _gs.harvester_place_mode or _gs.factory_place_mode or _gs.storage_place_mode or _gs.conveyor_place_mode) and _has_hover_cell:
		var world: WorldMap = _gs.world_map as WorldMap
		if _hover_cell.x >= 0 and _hover_cell.y >= 0 and _hover_cell.x < world.width and _hover_cell.y < world.height:
			var valid := false
			var ghost := Rect2(_hover_cell.x * d, _hover_cell.y * d, d - 1.0, d - 1.0)
			if _gs.shaft_place_mode:
				valid = _gs.can_place_shaft(_hover_cell)
			elif _gs.wheel_place_mode:
				valid = _gs.can_place_wheel(_hover_cell)
			elif _gs.harvester_place_mode:
				var sub_h := _hover_subcell
				valid = _gs.can_place_harvester(sub_h)
				var cells: Array = _gs.get_harvester_preview_cells(sub_h)
				if not cells.is_empty():
					ghost = _bounds_rect_for_subcells(cells, sub, 0.0)
			elif _gs.factory_place_mode:
				valid = _gs.can_place_factory(_hover_cell)
			elif _gs.storage_place_mode:
				valid = _gs.can_place_storage(_hover_cell)
			elif _gs.conveyor_place_mode:
				var sub_c := _hover_subcell
				valid = _gs.can_place_conveyor(sub_c)
				ghost = Rect2(float(sub_c.x) * sub, float(sub_c.y) * sub, sub - 1.0, sub - 1.0)
			draw_rect(ghost, GHOST_VALID_COLOR if valid else GHOST_INVALID_COLOR)
			draw_rect(ghost, SHAFT_BORDER_COLOR, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var d := _cell_display_px()
		var sub := d / float(_gs.PLACEMENT_SUBDIV)
		var local := get_local_mouse_position()
		_hover_cell = Vector2i(int(local.x / d), int(local.y / d))
		_hover_subcell = Vector2i(int(local.x / sub), int(local.y / sub))
		if _drag_place_conveyor and _gs.conveyor_place_mode and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_try_place_conveyor_at_subcell(_hover_subcell)
		_has_hover_cell = true
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var local := get_local_mouse_position()
		var d := _cell_display_px()
		var sub := d / float(_gs.PLACEMENT_SUBDIV)
		var tile_cell := Vector2i(int(local.x / d), int(local.y / d))
		var sub_cell := Vector2i(int(local.x / sub), int(local.y / sub))
		if _gs.try_pickup_placeable(sub_cell) or _gs.try_pickup_placeable(tile_cell):
			accept_event()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var w: WorldMap = _gs.world_map as WorldMap
		if w.width == 0:
			return
		var local := get_local_mouse_position()
		var d := _cell_display_px()
		var sub := d / float(_gs.PLACEMENT_SUBDIV)
		var cx := int(local.x / d)
		var cy := int(local.y / d)
		var cell := Vector2i(cx, cy)
		var sub_cell := Vector2i(int(local.x / sub), int(local.y / sub))
		if _gs.shaft_place_mode:
			if _gs.try_place_shaft(cell):
				accept_event()
				return
		elif _gs.wheel_place_mode:
			if _gs.try_place_wheel(cell):
				accept_event()
				return
		elif _gs.harvester_place_mode:
			if _gs.try_place_harvester(sub_cell):
				accept_event()
				return
		elif _gs.factory_place_mode:
			if _gs.try_place_factory(cell):
				accept_event()
				return
		elif _gs.storage_place_mode:
			if _gs.try_place_storage(cell):
				accept_event()
				return
		elif _gs.conveyor_place_mode:
			_drag_place_conveyor = true
			if _try_place_conveyor_at_subcell(sub_cell):
				accept_event()
				return
		if _gs.shaft_place_mode or _gs.wheel_place_mode or _gs.harvester_place_mode or _gs.factory_place_mode or _gs.storage_place_mode or _gs.conveyor_place_mode:
			var preferred_pickup := ""
			if _gs.shaft_place_mode:
				preferred_pickup = "shaft"
			elif _gs.conveyor_place_mode:
				preferred_pickup = "conveyor"
			var pick_cell := sub_cell if (_gs.conveyor_place_mode or _gs.harvester_place_mode) else cell
			if _gs.try_pickup_placeable(pick_cell, preferred_pickup):
				accept_event()
				return
		_gs.try_chop_tree(cell)
		_gs.try_mine_quarry(cell)
		accept_event()
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_place_conveyor = false


func _on_mouse_exited() -> void:
	_has_hover_cell = false
	queue_redraw()


func _is_current_phase(x: int) -> bool:
	var p := posmod(x + _flow_tick, RIVER_FLOW_WAVELENGTH)
	return p == 0


func _ensure_conveyor_flow_cache() -> void:
	if not _conveyor_flow_cache_dirty:
		return
	_conveyor_flow_dist = _build_conveyor_distance_field(_gs.get_placed_conveyors(), _gs.get_placed_factories(), _gs.get_placed_storages())
	_conveyor_flow_cache_dirty = false


func _build_conveyor_distance_field(conveyors: Dictionary, factories: Dictionary, storages: Dictionary) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = []
	var sinks: Dictionary = {}
	for sink: Vector2i in factories.keys():
		for n: Vector2i in _tile_sink_subcells(sink):
			sinks[n] = true
	for sink: Vector2i in storages.keys():
		for n: Vector2i in _tile_sink_subcells(sink):
			sinks[n] = true
	for n: Vector2i in sinks.keys():
		if conveyors.has(n) and not dist.has(n):
			dist[n] = 0
			queue.append(n)
	var i := 0
	while i < queue.size():
		var cur: Vector2i = queue[i]
		i += 1
		var cur_d: int = int(dist[cur])
		for dir: Vector2i in CARDINAL_DIRS:
			var n: Vector2i = cur + dir
			if not conveyors.has(n) or dist.has(n):
				continue
			dist[n] = cur_d + 1
			queue.append(n)
	return dist


func _tile_sink_subcells(tile: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := int(_gs.PLACEMENT_SUBDIV)
	var base := Vector2i(tile.x * s, tile.y * s)
	for i in s:
		out.append(Vector2i(base.x - 1, base.y + i))
		out.append(Vector2i(base.x + s, base.y + i))
		out.append(Vector2i(base.x + i, base.y - 1))
		out.append(Vector2i(base.x + i, base.y + s))
	return out


func _get_conveyor_flow_dir(cell: Vector2i, conveyors: Dictionary, dist: Dictionary) -> Vector2i:
	if dist.has(cell):
		var here: int = int(dist[cell])
		var best := Vector2i.ZERO
		var best_d := here
		for dir: Vector2i in CARDINAL_DIRS:
			var n: Vector2i = cell + dir
			if not dist.has(n):
				continue
			var nd: int = int(dist[n])
			if nd < best_d:
				best_d = nd
				best = dir
		if best != Vector2i.ZERO:
			return best
	for dir: Vector2i in CARDINAL_DIRS:
		if conveyors.has(cell + dir):
			return dir
	return Vector2i.ZERO


func _bounds_rect_for_subcells(cells: Array, sub_cell_px: float, inset: float) -> Rect2:
	var min_x := 1_000_000
	var min_y := 1_000_000
	var max_x := -1_000_000
	var max_y := -1_000_000
	for sc in cells:
		var s: Vector2i = sc
		min_x = mini(min_x, s.x)
		min_y = mini(min_y, s.y)
		max_x = maxi(max_x, s.x)
		max_y = maxi(max_y, s.y)
	return Rect2(
		float(min_x) * sub_cell_px + inset,
		float(min_y) * sub_cell_px + inset,
		float(max_x - min_x + 1) * sub_cell_px - inset * 2.0,
		float(max_y - min_y + 1) * sub_cell_px - inset * 2.0
	)


func _get_visible_map_rect() -> Rect2:
	var parent := get_parent()
	if parent is ScrollContainer:
		var sc: ScrollContainer = parent as ScrollContainer
		var origin := Vector2(sc.scroll_horizontal, sc.scroll_vertical)
		return Rect2(origin, sc.size)
	return Rect2(Vector2.ZERO, size)


func _is_rect_visible(rect: Rect2, view_rect: Rect2) -> bool:
	var pad := 12.0
	var expanded := Rect2(view_rect.position - Vector2(pad, pad), view_rect.size + Vector2(pad * 2.0, pad * 2.0))
	return expanded.intersects(rect)
