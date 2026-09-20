class_name ActionButton
extends Control
## Plain HUD button (no texture assets): draws a rounded pill with a label and
## emits `pressed` on a real click/tap. Used for non-ability actions.

signal pressed

@export var label: String = ""
@export var button_color: Color = Color(0.55, 0.62, 0.75)
@export var font_size: int = 20

var _hovered: bool = false
var _held: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_held = true
		elif _held:
			_held = false
			pressed.emit()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = true
		elif _held:
			_held = false
			pressed.emit()
		accept_event()
	elif event is InputEventMouseMotion:
		var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
		if inside != _hovered:
			_hovered = inside
			queue_redraw()
		accept_event()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var alpha := 0.30 if _hovered else 0.20
	draw_rect(rect, Color(button_color, alpha))
	draw_rect(rect, Color(button_color, 0.95), false, 3.0)
	if not label.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(0.0, size.y * 0.5 + font_size * 0.36), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(1.0, 1.0, 1.0, 0.95))
