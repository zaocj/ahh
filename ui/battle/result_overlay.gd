class_name ResultOverlay
extends Control
## End-of-match panel: dimmed backdrop, result title, cause and a rematch button.
##
## Presentation only - it renders what MatchDirector decided and asks for a
## restart, so it never inspects vitals or timers itself. It runs with
## PROCESS_MODE_ALWAYS because the match pauses the tree while the overlay is up,
## and the rematch button has to stay clickable behind that pause.

signal restart_requested

const DIM_COLOR: Color = Color(0.03, 0.04, 0.07, 0.74)
const PANEL_SIZE: Vector2 = Vector2(480.0, 260.0)
const PANEL_FILL: Color = Color(0.08, 0.10, 0.15, 0.96)
const PANEL_BORDER: Color = Color(0.55, 0.62, 0.75, 0.55)

@onready var _title: Label = $Title
@onready var _reason: Label = $Reason
@onready var _rematch: ActionButton = $Rematch

func _ready() -> void:
	# Shown while the tree is paused: the overlay must still draw and click.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rematch.pressed.connect(_on_rematch_pressed)
	hide()

## `accent` colors the title (green for a win, red for a loss, amber for a draw).
func show_result(title: String, reason: String, accent: Color) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", accent)
	_reason.text = reason
	show()
	queue_redraw()

func _on_rematch_pressed() -> void:
	restart_requested.emit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM_COLOR)
	var panel := Rect2(size * 0.5 - PANEL_SIZE * 0.5, PANEL_SIZE)
	draw_rect(panel, PANEL_FILL)
	draw_rect(panel, PANEL_BORDER, false, 3.0)
