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
	var direction := _input_direction()
	var target_velocity := direction * speed
	var rate := acceleration if direction != Vector2.ZERO else friction
	velocity = velocity.move_toward(target_velocity, rate * delta)

	var before := global_position
	move_and_slide()
	var travelled := global_position - before
	if travelled.length() > 0.01:
		moved.emit(travelled.normalized())

	is_blocked = direction != Vector2.ZERO and is_on_wall()
	if is_blocked:
		blocked.emit(direction)

## Keyboard/gamepad actions take priority unless the joystick pushes further.
func _input_direction() -> Vector2:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if joystick_input.length() > direction.length():
		direction = joystick_input
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction
