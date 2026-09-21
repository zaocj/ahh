class_name ResultOverlay
extends Control
## End-of-match panel: result, cause, scoreboard (hero / kills / damage) and rematch.
##
## Presentation only - it renders what MatchDirector decided and what MatchStats
## recorded, and asks for a restart. It runs with PROCESS_MODE_ALWAYS because the
## match pauses the tree while the overlay is up, and the rematch button has to stay
## clickable behind that pause.

signal restart_requested

const DIM_COLOR: Color = Color(0.03, 0.04, 0.07, 0.74)
const PANEL_SIZE: Vector2 = Vector2(640.0, 470.0)
const PANEL_FILL: Color = Color(0.08, 0.10, 0.15, 0.96)
const PANEL_BORDER: Color = Color(0.55, 0.62, 0.75, 0.55)
const HEADER_COLOR: Color = Color(0.62, 0.68, 0.78, 0.9)
const ROW_COLOR: Color = Color(0.92, 0.94, 0.98, 0.95)
const ROW_DIM: Color = Color(0.55, 0.58, 0.64, 0.85)
const ROW_HEIGHT: float = 36.0
const ROW_TOP_FROM_CENTER: float = -62.0
const CHIP: Vector2 = Vector2(16.0, 16.0)
const NAME_COLUMN: float = 230.0
const KILLS_COLUMN: float = 350.0
const DAMAGE_COLUMN: float = 430.0

@onready var _title: Label = $Title
@onready var _reason: Label = $Reason
@onready var _rematch: ActionButton = $Rematch

var _rows: Array[Dictionary] = []

func _ready() -> void:
	# Shown while the tree is paused: the overlay must still draw and click.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rematch.pressed.connect(_on_rematch_pressed)
	hide()

## `accent` colors the title; `rows` is `MatchStats.rows()` - hero name, team, kills
## and damage per participant.
func show_result(title: String, reason: String, accent: Color, rows: Array[Dictionary] = []) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", accent)
	_reason.text = reason
	_rows = rows
	show()
	queue_redraw()

func _on_rematch_pressed() -> void:
	restart_requested.emit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM_COLOR)
	var panel := Rect2(size * 0.5 - PANEL_SIZE * 0.5, PANEL_SIZE)
	draw_rect(panel, PANEL_FILL)
	draw_rect(panel, PANEL_BORDER, false, 3.0)
	_draw_scoreboard(size * 0.5)

func _draw_scoreboard(center: Vector2) -> void:
	var left := center.x - PANEL_SIZE.x * 0.5 + 34.0
	var header_y := center.y + ROW_TOP_FROM_CENTER - 16.0
	var font := ThemeDB.fallback_font
	for column in [[left + 26.0, "HERO"], [left + KILLS_COLUMN, "KILLS"], [left + DAMAGE_COLUMN, "DAMAGE"]]:
		draw_string(font, Vector2(column[0], header_y), column[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HEADER_COLOR)

	var y := header_y + 10.0
	for row in _rows:
		y += ROW_HEIGHT
		var alive := bool(row.get("alive", true))
		var text_color := ROW_COLOR if alive else ROW_DIM
		var chip_color := Teams.color_of(int(row.get("team", Teams.Id.BLUE)))
		if not alive:
			chip_color.a = 0.4
		draw_rect(Rect2(Vector2(left, y - 14.0), CHIP), chip_color)
		var label := String(row.get("name", "?"))
		if bool(row.get("human", false)):
			label += "  (you)"
		if not alive:
			label += "  - down"
		draw_string(font, Vector2(left + 26.0, y), label,
			HORIZONTAL_ALIGNMENT_LEFT, NAME_COLUMN - 32.0, 19, text_color)
		draw_string(font, Vector2(left + KILLS_COLUMN, y), str(int(row.get("kills", 0))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, text_color)
		draw_string(font, Vector2(left + DAMAGE_COLUMN, y), str(int(row.get("damage", 0))),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, text_color)
