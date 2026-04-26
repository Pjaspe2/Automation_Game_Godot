extends Control

## Renders `GameState.world_map` with Kenney Tiny Town tiles (`tilemap_packed.png`).

const MAP_SCALE := 2.0
const RIVER_COLOR := Color(0.20, 0.48, 0.90, 0.95)
const RIVER_CURRENT_COLOR := Color(0.92, 0.97, 1.0, 0.45)
const RIVER_CURRENT_LINE_COLOR := Color(1.0, 1.0, 1.0, 0.75)
const QUARRY_COOLDOWN_SHADE := Color(0.22, 0.22, 0.22, 0.6)
const SHAFT_COLOR := Color(0.55, 0.36, 0.20, 0.95)
const SHAFT_BORDER_COLOR := Color(0.16, 0.10, 0.06, 1.0)
const POWERED_SHAFT_GLOW := Color(1.0, 0.95, 0.55, 0.35)
const WHEEL_COLOR := Color(0.35, 0.22, 0.08, 0.95)
const WHEEL_BORDER_COLOR := Color(0.12, 0.07, 0.03, 1.0)
const FACTORY_COLOR := Color(0.58, 0.42, 0.22, 0.95)
const FACTORY_STARVED_COLOR := Color(0.34, 0.28, 0.24, 0.95)
const FACTORY_BORDER_COLOR := Color(0.18, 0.12, 0.06, 1.0)
const HARVESTER_BORDER_COLOR := Color(0.2, 0.2, 0.24, 1.0)
const HARVESTER_WOOD_COLOR := Color(0.38, 0.72, 0.38, 0.95)
const HARVESTER_STONE_COLOR := Color(0.72, 0.72, 0.78, 0.95)
const HELPER_WOOD_COLOR := Color(0.32, 0.88, 0.40, 0.25)
const HELPER_STONE_COLOR := Color(0.75, 0.80, 0.92, 0.25)
const GHOST_VALID_COLOR := Color(0.25, 0.95, 0.35, 0.38)
const GHOST_INVALID_COLOR := Color(0.95, 0.20, 0.20, 0.42)
const RIVER_FLOW_STEP_SEC := 0.16
const RIVER_FLOW_WAVELENGTH := 4

@onready var _layer: TileMapLayer = $TileMapLayer

var _source_id: int = 0
var _hover_cell := Vector2i(-1, -1)
var _has_hover_cell := false
var _flow_tick := 0
var _flow_accum := 0.0


func _ready() -> void:
	_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	# Keep tile sprites behind this Control's overlay draw calls (river/shaft/ghost markers).
	_layer.z_index = -1
	_build_tileset()
	mouse_exited.connect(_on_mouse_exited)
	GameState.world_changed.connect(_on_world_changed)
	_on_world_changed()


func _cell_display_px() -> float:
	return float(TinyTownAtlas.TILE_PX) * MAP_SCALE


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
	var w := GameState.world_map
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
	var w := GameState.world_map
	_layer.clear()
	if w.width == 0 or _layer.tile_set == null:
		return
	for y in w.height:
		for x in w.width:
			var kind: int = w.cells[y * w.width + x]
			if kind == WorldMap.Cell.RIVER:
				# River is intentionally a flat color for readability.
				continue
			var ac := TinyTownAtlas.atlas_for_cell(kind)
			_layer.set_cell(Vector2i(x, y), _source_id, ac)


func _draw() -> void:
	var w := GameState.world_map
	if w.width == 0:
		return
	var d := _cell_display_px()
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
			if w.cells[y * w.width + x] != WorldMap.Cell.QUARRY:
				continue
			var cooldown_ratio := GameState.get_quarry_cooldown_ratio(Vector2i(x, y))
			if cooldown_ratio <= 0.0:
				continue
			var shade := Color(QUARRY_COOLDOWN_SHADE.r, QUARRY_COOLDOWN_SHADE.g, QUARRY_COOLDOWN_SHADE.b, QUARRY_COOLDOWN_SHADE.a * cooldown_ratio)
			var rect := Rect2(x * d, y * d, d - 1.0, d - 1.0)
			draw_rect(rect, shade)
	var shafts := GameState.get_placed_shafts()
	var powered_shafts := GameState.get_powered_shafts()
	for c: Vector2i in shafts.keys():
		var inset := d * 0.2
		var rect := Rect2(c.x * d + inset, c.y * d + inset, d - inset * 2.0, d - inset * 2.0)
		if powered_shafts.has(c):
			var glow := Rect2(c.x * d + d * 0.08, c.y * d + d * 0.08, d - d * 0.16, d - d * 0.16)
			draw_rect(glow, POWERED_SHAFT_GLOW)
		draw_rect(rect, SHAFT_COLOR)
		draw_rect(rect, SHAFT_BORDER_COLOR, false, 2.0)
		# Simple axle stripe so placed shafts are easier to identify at a glance.
		var mid_y := rect.position.y + rect.size.y * 0.5
		draw_line(Vector2(rect.position.x + 3.0, mid_y), Vector2(rect.position.x + rect.size.x - 3.0, mid_y), SHAFT_BORDER_COLOR, 2.0)
	for c: Vector2i in GameState.get_placed_wheels().keys():
		var rect := Rect2(c.x * d + d * 0.18, c.y * d + d * 0.18, d * 0.64, d * 0.64)
		draw_rect(rect, WHEEL_COLOR)
		draw_rect(rect, WHEEL_BORDER_COLOR, false, 2.0)
		var x_mid := rect.position.x + rect.size.x * 0.5
		var y_mid := rect.position.y + rect.size.y * 0.5
		draw_line(Vector2(x_mid, rect.position.y + 2.0), Vector2(x_mid, rect.position.y + rect.size.y - 2.0), WHEEL_BORDER_COLOR, 2.0)
		draw_line(Vector2(rect.position.x + 2.0, y_mid), Vector2(rect.position.x + rect.size.x - 2.0, y_mid), WHEEL_BORDER_COLOR, 2.0)
	for c: Vector2i in GameState.get_placed_factories().keys():
		var rect := Rect2(c.x * d + d * 0.12, c.y * d + d * 0.12, d * 0.76, d * 0.76)
		var fed := GameState.get_factory_input_satisfaction() >= 0.999
		draw_rect(rect, FACTORY_COLOR if fed else FACTORY_STARVED_COLOR)
		draw_rect(rect, FACTORY_BORDER_COLOR, false, 2.0)
		var roof := Rect2(rect.position.x + 3.0, rect.position.y + 3.0, rect.size.x - 6.0, rect.size.y * 0.4)
		draw_rect(roof, Color(0.72, 0.55, 0.32, 0.95))
		var smoke_x := rect.position.x + rect.size.x * 0.76
		if fed:
			draw_line(Vector2(smoke_x, rect.position.y + 4.0), Vector2(smoke_x, rect.position.y - 4.0), FACTORY_BORDER_COLOR, 2.0)
	for c: Vector2i in GameState.get_placed_harvesters().keys():
		var rect := Rect2(c.x * d + d * 0.16, c.y * d + d * 0.16, d * 0.68, d * 0.68)
		var role := GameState.get_harvester_role(c)
		draw_rect(rect, HARVESTER_WOOD_COLOR if role == "wood" else HARVESTER_STONE_COLOR)
		draw_rect(rect, HARVESTER_BORDER_COLOR, false, 2.0)
		var pipe_y := rect.position.y + rect.size.y * 0.72
		draw_line(Vector2(rect.position.x + 4.0, pipe_y), Vector2(rect.position.x + rect.size.x - 4.0, pipe_y), HARVESTER_BORDER_COLOR, 2.0)
	if GameState.harvester_place_mode:
		var candidates := GameState.get_harvester_candidate_roles()
		for c: Vector2i in candidates.keys():
			var rect := Rect2(c.x * d, c.y * d, d - 1.0, d - 1.0)
			var role := str(candidates[c])
			draw_rect(rect, HELPER_WOOD_COLOR if role == "wood" else HELPER_STONE_COLOR)
	if (GameState.shaft_place_mode or GameState.wheel_place_mode or GameState.harvester_place_mode or GameState.factory_place_mode) and _has_hover_cell:
		var world := GameState.world_map
		if _hover_cell.x >= 0 and _hover_cell.y >= 0 and _hover_cell.x < world.width and _hover_cell.y < world.height:
			var ghost := Rect2(_hover_cell.x * d, _hover_cell.y * d, d - 1.0, d - 1.0)
			var valid := false
			if GameState.shaft_place_mode:
				valid = GameState.can_place_shaft(_hover_cell)
			elif GameState.wheel_place_mode:
				valid = GameState.can_place_wheel(_hover_cell)
			elif GameState.harvester_place_mode:
				valid = GameState.can_place_harvester(_hover_cell)
			elif GameState.factory_place_mode:
				valid = GameState.can_place_factory(_hover_cell)
			draw_rect(ghost, GHOST_VALID_COLOR if valid else GHOST_INVALID_COLOR)
			draw_rect(ghost, SHAFT_BORDER_COLOR, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var d := _cell_display_px()
		var local := get_local_mouse_position()
		_hover_cell = Vector2i(int(local.x / d), int(local.y / d))
		_has_hover_cell = true
		queue_redraw()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var local := get_local_mouse_position()
		var d := _cell_display_px()
		var cell := Vector2i(int(local.x / d), int(local.y / d))
		if GameState.try_pickup_placeable(cell):
			accept_event()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var w := GameState.world_map
		if w.width == 0:
			return
		var local := get_local_mouse_position()
		var d := _cell_display_px()
		var cx := int(local.x / d)
		var cy := int(local.y / d)
		var cell := Vector2i(cx, cy)
		if GameState.shaft_place_mode or GameState.wheel_place_mode or GameState.harvester_place_mode or GameState.factory_place_mode:
			if GameState.try_pickup_placeable(cell):
				accept_event()
				return
		if GameState.shaft_place_mode:
			if GameState.try_place_shaft(cell):
				accept_event()
				return
		elif GameState.wheel_place_mode:
			if GameState.try_place_wheel(cell):
				accept_event()
				return
		elif GameState.harvester_place_mode:
			if GameState.try_place_harvester(cell):
				accept_event()
				return
		elif GameState.factory_place_mode:
			if GameState.try_place_factory(cell):
				accept_event()
				return
		GameState.try_chop_tree(cell)
		GameState.try_mine_quarry(cell)
		accept_event()


func _on_mouse_exited() -> void:
	_has_hover_cell = false
	queue_redraw()


func _is_current_phase(x: int) -> bool:
	var p := posmod(x + _flow_tick, RIVER_FLOW_WAVELENGTH)
	return p == 0
