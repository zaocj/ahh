extends TileMapLayer
## Top-down arena terrain.
##
## The layout below is one character per cell: "#" wall, "." floor, "o" spawn pad.
## Floor variants are chosen deterministically so the arena does not look uniform.
## Cells are painted in _ready() because the agent bridge has no tile-painting
## capability yet; painting the same grid by hand in the TileMap panel is a
## drop-in replacement for this script.

const SOURCE_ID: int = 0
const FLOOR: Vector2i = Vector2i(0, 0)
const FLOOR_VARIANT: Vector2i = Vector2i(1, 0)
const WALL: Vector2i = Vector2i(2, 0)
const SPAWN_PAD: Vector2i = Vector2i(3, 0)

const ARENA_WIDTH: int = 40

## Cells painted by the last _paint_arena() pass; exposed for debugging and tests.
var painted_cells: int = 0

const ARENA: PackedStringArray = [
	"########################################",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"#.......................###............#",
	"#.....######................#..........#",
	"#.....######...........................#",
	"#......................................#",
	"#.............................##.......#",
	"#.............................##.......#",
	"#.............................##.......#",
	"#...................o.........##.......#",
	"#.............................##.......#",
	"#.............................##.......#",
	"#........##............................#",
	"#......................................#",
	"#..............####....................#",
	"#..............####....................#",
	"#..............####....................#",
	"#..............####....................#",
	"#......................................#",
	"########################################",
]

func _ready() -> void:
	_paint_arena()

func _paint_arena() -> void:
	painted_cells = 0
	for y in ARENA.size():
		var row: String = ARENA[y]
		if row.length() != ARENA_WIDTH:
			push_error("Arena row %d has %d cells, expected %d." % [y, row.length(), ARENA_WIDTH])
			continue
		for x in row.length():
			var cell := Vector2i(x, y)
			match row[x]:
				"#":
					set_cell(cell, SOURCE_ID, WALL)
				"o":
					set_cell(cell, SOURCE_ID, SPAWN_PAD)
				_:
					set_cell(cell, SOURCE_ID, FLOOR_VARIANT if (x * 7 + y * 3) % 11 == 0 else FLOOR)
			painted_cells += 1

## World-space centre of a cell, using the layer's own tile size.
func cell_center(cell: Vector2i) -> Vector2:
	return map_to_local(cell)
