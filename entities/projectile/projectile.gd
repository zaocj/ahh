class_name Projectile
extends Area2D
## Generic flying projectile: constant speed along one direction, gone once it
## has travelled `max_distance` or touched anything solid.
##
## Skills spawn and parameterise it (see skills/actions/spawn_projectile_action.gd);
## it never reaches back into the skill that fired it.
##
## Collision layers: 1 = world/walls, 2 = characters, 3 = projectiles.
## The projectile scans 1 and 2, and ignores whoever fired it.

signal travelled(distance: float)

@export var speed: float = 520.0
@export var max_distance: float = 480.0

var direction: Vector2 = Vector2.RIGHT
var distance_travelled: float = 0.0

var _caster: Node = null

@onready var _body: Polygon2D = $Body
@onready var _collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_fit_body_to_collision_shape()
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

## Applies the launch parameters. `caster` is ignored on impact so a shot cannot
## hit whoever fired it.
func launch(new_direction: Vector2, launch_speed: float, range_distance: float, caster: Node = null) -> void:
	direction = new_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	speed = launch_speed
	max_distance = range_distance
	_caster = caster
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	distance_travelled += step
	travelled.emit(distance_travelled)
	if distance_travelled >= max_distance:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == _caster:
		return
	queue_free()

## Mirrors Player: the placeholder block is derived from the collision shape so
## no PackedVector2Array has to be stored in the scene.
func _fit_body_to_collision_shape() -> void:
	var shape: Shape2D = _collision.shape
	if shape is not RectangleShape2D:
		push_warning("Projectile has no RectangleShape2D; using the default block.")
	var shape_size: Vector2 = (shape as RectangleShape2D).size if shape is RectangleShape2D else Vector2(18, 12)
	var half := shape_size * 0.5
	_body.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
