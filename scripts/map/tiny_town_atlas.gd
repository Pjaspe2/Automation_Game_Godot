extends Object
class_name TinyTownAtlas

## Kenney Tiny Town — `Tilemap/tilemap_packed.png` (12×11 tiles @ 16×16, no spacing).
## Atlas coords are (column, row). Tweak here if you want different sprites per cell type.

const TEXTURE_PATH := "res://kenney_tiny-town/Tilemap/tilemap_packed.png"
const TILE_PX := 16

const ATLAS: Dictionary = {
	WorldMap.Cell.GRASS: Vector2i(0, 0),
	WorldMap.Cell.HOME: Vector2i(7, 7),
	WorldMap.Cell.RIVER: Vector2i(1, 8),
	WorldMap.Cell.TREE: Vector2i(6, 1),
	WorldMap.Cell.STUMP: Vector2i(2, 2),
	WorldMap.Cell.QUARRY: Vector2i(7, 4),
	WorldMap.Cell.COPPER_MINE: Vector2i(9, 2),
}


static func atlas_for_cell(kind: int) -> Vector2i:
	return ATLAS.get(kind, Vector2i(0, 0))
