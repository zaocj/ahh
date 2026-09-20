class_name SkillButton
extends Control
## HUD skill button: tap to cast, hold and drag to aim.
##
## It only translates pointer events into positions relative to the button centre
## and forwards them to SkillController - no skill logic lives here. Cooldown is
## drawn as a dark pie over the button.

signal pressed_at(position: Vector2)
signal dragged_to(position: Vector2)
signal released_at(position: Vector2)
## The pointer went away without a release (touch cancelled by the OS);
## the skill must not be cast.
signal cancelled

const NO_POINTER: int = -1

@export var button_color: Color = Color(0.24, 0.78, 0.94)
@export var label: String = ""

var _pointer_id: int = NO_POINTER
var _cooldown_ratio: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

## Called when wiring the HUD: takes the look from the skill itself.
func setup(skill: SkillData) -> void:
	if skill == null:
		return
	button_color = skill.icon_color
	label = skill.display_name
	queue_redraw()

## 0.0 = ready, 1.0 = just went on cooldown.
func set_cooldown_ratio(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _cooldown_ratio):
		return
	_cooldown_ratio = clamped
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled:
			if event.index == _pointer_id:
				_pointer_id = NO_POINTER
				cancelled.emit()
			accept_event()
		elif event.pressed and _pointer_id == NO_POINTER:
			_press(event.index, event.position)
			accept_event()
		elif not event.pressed and event.index == _pointer_id:
			_release(event.position)
			accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _pointer_id:
			dragged_to.emit(_centered(event.position))
			accept_event()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed and _pointer_id == NO_POINTER:
			_press(NO_POINTER, event.position)
			accept_event()
		elif not event.pressed and _pointer_id == NO_POINTER:
			_release(event.position)
			accept_event()
	elif event is InputEventMouseMotion and _pointer_id == NO_POINTER:
		dragged_to.emit(_centered(event.position))
		accept_event()

func _press(pointer_id: int, position: Vector2) -> void:
	_pointer_id = pointer_id
	pressed_at.emit(_centered(position))

func _release(position: Vector2) -> void:
	_pointer_id = NO_POINTER
	released_at.emit(_centered(position))

func _centered(position: Vector2) -> Vector2:
	return position - size * 0.5

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center, radius, Color(button_color, 0.22))
	draw_arc(center, radius, 0.0, TAU, 48, Color(button_color, 0.9), 3.0, true)
	if _cooldown_ratio > 0.0:
		_draw_cooldown_pie(center, radius)
	if not label.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(0.0, center.y + 7.0),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			20,
			Color(1.0, 1.0, 1.0, 0.95)
		)

## Remaining cooldown sweeps clockwise from the top, like most action games.
func _draw_cooldown_pie(center: Vector2, radius: float) -> void:
	const STEPS: int = 32
	var points := PackedVector2Array([center])
	var sweep := TAU * _cooldown_ratio
	for i in STEPS + 1:
		var angle := -PI * 0.5 + sweep * float(i) / float(STEPS)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(0.05, 0.06, 0.10, 0.6))
