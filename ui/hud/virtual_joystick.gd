extends Control
## On-screen joystick for touch and mouse. Press anywhere inside the control,
## drag, and release; the knob stays inside the base and the emitted vector is
## already dead-zoned and normalized to length 0..1.

signal vector_changed(vector: Vector2)

const DEAD_ZONE: float = 0.14
const NO_POINTER: int = -1

@export var base_radius: float = 96.0
@export var knob_radius: float = 40.0
@export var base_color: Color = Color(0.09, 0.11, 0.16, 0.55)
@export var rim_color: Color = Color(0.55, 0.65, 0.80, 0.65)
@export var knob_color: Color = Color(0.24, 0.78, 0.94, 0.92)

var _pointer_id: int = NO_POINTER
var _knob_offset: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _pointer_id == NO_POINTER:
			_press(event.index, event.position)
			accept_event()
		elif not event.pressed and event.index == _pointer_id:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _pointer_id:
			_drag(event.position)
			accept_event()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed and _pointer_id == NO_POINTER:
			_press(NO_POINTER, event.position)
			accept_event()
		elif not event.pressed and _pointer_id == NO_POINTER:
			_release()
			accept_event()
	elif event is InputEventMouseMotion and _pointer_id == NO_POINTER:
		_drag(event.position)
		accept_event()

func _press(pointer_id: int, local_position: Vector2) -> void:
	_pointer_id = pointer_id
	_drag(local_position)

func _drag(local_position: Vector2) -> void:
	if _pointer_id == NO_POINTER and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var offset := local_position - size * 0.5
	if offset.length() > base_radius:
		offset = offset.normalized() * base_radius
	_knob_offset = offset
	_set_value(_shape(offset))

func _release() -> void:
	_pointer_id = NO_POINTER
	_knob_offset = Vector2.ZERO
	_set_value(Vector2.ZERO)

## Maps the raw stick offset to a dead-zoned vector of length 0..1.
func _shape(offset: Vector2) -> Vector2:
	var length := offset.length() / base_radius
	if length <= DEAD_ZONE:
		return Vector2.ZERO
	return offset.normalized() * inverse_lerp(DEAD_ZONE, 1.0, minf(length, 1.0))

func _set_value(value: Vector2) -> void:
	queue_redraw()
	if value.is_equal_approx(_value):
		return
	_value = value
	vector_changed.emit(_value)

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, base_radius, base_color)
	draw_arc(center, base_radius, 0.0, TAU, 64, rim_color, 3.0, true)
	draw_circle(center + _knob_offset, knob_radius, knob_color)
