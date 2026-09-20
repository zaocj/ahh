class_name SkillIndicator
extends Node2D
## Generic aiming indicator. Knows nothing about any specific skill: it draws
## whatever SkillIndicatorData it is handed, always along its own +X axis, and
## the controller aims it by setting rotation/global position.

var _data: SkillIndicatorData

func _ready() -> void:
	# Driven in world space; the caster's transform and y-sorting must not apply.
	top_level = true
	z_index = 100
	visible = false

## Shows the indicator described by `data`; a null data hides it.
func show_indicator(data: SkillIndicatorData) -> void:
	if data == null:
		hide_indicator()
		return
	_data = data
	visible = true
	queue_redraw()

func hide_indicator() -> void:
	visible = false

func is_active() -> bool:
	return visible

## Points the indicator; callers keep the last direction themselves.
func set_direction(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	rotation = direction.angle()

func _draw() -> void:
	if _data == null:
		return
	match _data.shape:
		SkillIndicatorData.Shape.CIRCLE:
			_draw_circle()
		SkillIndicatorData.Shape.LINE:
			_draw_outline(_shaft_points(), false)
		_:
			_draw_outline(_arrow_points(), true)

func _shaft_points() -> PackedVector2Array:
	var half := _data.width * 0.5
	return PackedVector2Array([
		Vector2(0.0, -half),
		Vector2(_data.length, -half),
		Vector2(_data.length, half),
		Vector2(0.0, half),
	])

## Arrow head is twice as wide as the shaft, kept inside the total length.
func _arrow_points() -> PackedVector2Array:
	var half := _data.width * 0.5
	var head := minf(_data.head_length, _data.length)
	var shaft_end := _data.length - head
	return PackedVector2Array([
		Vector2(0.0, -half),
		Vector2(shaft_end, -half),
		Vector2(shaft_end, -_data.width),
		Vector2(_data.length, 0.0),
		Vector2(shaft_end, _data.width),
		Vector2(shaft_end, half),
		Vector2(0.0, half),
	])

func _draw_outline(points: PackedVector2Array, with_origin_dot: bool) -> void:
	draw_colored_polygon(points, _data.fill_color)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, _data.outline_color, _data.outline_width, true)
	if with_origin_dot:
		draw_circle(Vector2.ZERO, maxf(_data.width, 8.0), _data.outline_color)

func _draw_circle() -> void:
	draw_circle(Vector2.ZERO, _data.length, _data.fill_color)
	draw_arc(Vector2.ZERO, _data.length, 0.0, TAU, 64, _data.outline_color, _data.outline_width, true)
