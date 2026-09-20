class_name Player
extends CharacterBody2D
## Top-down arena player: a colored square driven by the named movement actions
## or by the on-screen joystick.
##
## The body runs in floating motion mode because the arena has no gravity and no
## floor concept: every collision is a wall.

signal moved(direction: Vector2)
signal blocked(direction: Vector2)

@export var speed: float = 220.0
@export var acceleration: float = 2600.0
@export var friction: float = 3200.0

## Direction pushed by the on-screen joystick; combined with the key actions.
var joystick_input: Vector2 = Vector2.ZERO

## Last direction the player moved/faced. Skills use it as the default cast
## direction (taps fire straight ahead).
var facing: Vector2 = Vector2.RIGHT

var _dash_direction: Vector2 = Vector2.ZERO
var _dash_speed: float = 0.0
var _dash_remaining: float = 0.0
var _dash_active: bool = false

## True while the player pushes into a wall during the latest physics step.
var is_blocked: bool = false

@onready var _body: Polygon2D = $Body
@onready var _collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_fit_body_to_collision_shape()

## The agent bridge cannot express a PackedVector2Array, so the placeholder
## square is derived from the collision shape instead of stored in the scene.
func _fit_body_to_collision_shape() -> void:
	var shape: Shape2D = _collision.shape
	if shape is not RectangleShape2D:
		push_warning("Player has no RectangleShape2D; using the default square.")
	var half: Vector2 = (shape as RectangleShape2D).size * 0.5 if shape is RectangleShape2D else Vector2(14, 14)
	_body.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	var was_dashing := _dash_active
	if _dash_active:
		# One dash step, never overshooting the remaining distance.
		var step := minf(_dash_speed * delta, _dash_remaining)
		_dash_remaining = maxf(_dash_remaining - step, 0.0)
		_dash_active = _dash_remaining > 0.0
		velocity = _dash_direction * step / maxf(delta, 0.0001)
	else:
		direction = _input_direction()
		if direction != Vector2.ZERO:
			facing = direction
		var target_velocity := direction * speed
		var rate := acceleration if direction != Vector2.ZERO else friction
		velocity = velocity.move_toward(target_velocity, rate * delta)

	var before := global_position
	move_and_slide()
	var travelled := global_position - before
	if travelled.length() > 0.01:
		moved.emit(travelled.normalized())

	# A dash ends without inertia, otherwise the leftover speed slides the player
	# well past the configured distance.
	if was_dashing and not _dash_active:
		velocity = Vector2.ZERO

	is_blocked = direction != Vector2.ZERO and is_on_wall()
	if is_blocked:
		blocked.emit(direction)

## Called by DashAction: slide `distance` pixels along `direction`.
func dash(direction: Vector2, distance: float, duration: float) -> void:
	if direction == Vector2.ZERO or distance <= 0.0 or duration <= 0.0:
		return
	facing = direction.normalized()
	_dash_direction = facing
	_dash_speed = distance / duration
	_dash_remaining = distance
	_dash_active = true

func is_dashing() -> bool:
	return _dash_active

## Keyboard/gamepad actions take priority unless the joystick pushes further.
func _input_direction() -> Vector2:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if joystick_input.length() > direction.length():
		direction = joystick_input
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction
