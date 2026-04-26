extends RefCounted
class_name WorldMap

## Data-only grid for authored regions. Visuals live in `MapGridView`.

enum Cell {
	GRASS,
	HOME,
	RIVER,
	TREE,
	STUMP,
	QUARRY,
	COPPER_MINE,
}

const _CHAR := {
	".": Cell.GRASS,
	"H": Cell.HOME,
	"~": Cell.RIVER,
	"T": Cell.TREE,
	"Q": Cell.QUARRY,
	"M": Cell.COPPER_MINE,
}

var width: int
var height: int
var cells: PackedInt32Array


func _init(p_width: int, p_height: int, p_cells: PackedInt32Array) -> void:
	width = p_width
	height = p_height
	cells = p_cells


func cell_at(p: Vector2i) -> int:
	if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
		return Cell.GRASS
	return cells[p.y * width + p.x]


func set_cell(p: Vector2i, value: int) -> void:
	if p.x < 0 or p.y < 0 or p.x >= width or p.y >= height:
		return
	cells[p.y * width + p.x] = value


static func from_rows(rows: PackedStringArray) -> WorldMap:
	var h := rows.size()
	if h == 0:
		return WorldMap.new(0, 0, PackedInt32Array())
	var w := rows[0].length()
	var buf: PackedInt32Array = []
	buf.resize(w * h)
	for y in h:
		var row := rows[y]
		if row.length() != w:
			push_error("WorldMap.from_rows: ragged row %d" % y)
		for x in mini(row.length(), w):
			var ch := row[x]
			buf[y * w + x] = int(_CHAR.get(ch, Cell.GRASS))
	return WorldMap.new(w, h, buf)


static func starter() -> WorldMap:
	return from_rows(PackedStringArray([
		"TTT..T...T....T..T",
		"TTT..T...T....T..T",
		"..HHH...T...T..T..",
		"..HHH...T...T..T..",
		"........T...T.....",
		"~~~~~~~~~~~~~~~~~~",
		"~~~~~~~~..~~~~~~~~",
		"................TT",
		"..TTT...........TT",
		"....T..TT.TT......",
		"....T..TT.TT......",
		"..................",
		"..................",
		"..................",
	]))


static func expansion_strip() -> PackedStringArray:
	return PackedStringArray([
		"QQQQ...........",
		"QQQQ...........",
		"QQQQ......MMM..",
		"...Q......MMM..",
		"...Q......MMM..",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
	])


static func expanded(base: WorldMap) -> WorldMap:
	var add := expansion_strip()
	if add.is_empty():
		return base
	var add_w := add[0].length()
	var new_w := base.width + add_w
	var new_h: int = maxi(base.height, add.size())
	var buf: PackedInt32Array = []
	buf.resize(new_w * new_h)
	buf.fill(Cell.GRASS)
	for y in base.height:
		for x in base.width:
			buf[y * new_w + x] = base.cells[y * base.width + x]
	for y in add.size():
		var row := add[y]
		for x in row.length():
			var ch := row[x]
			buf[y * new_w + base.width + x] = int(_CHAR.get(ch, Cell.GRASS))
	return WorldMap.new(new_w, new_h, buf)
