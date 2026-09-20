class_name Projectile
extends Area2D
## 2D projectile transport: flies in a straight line, then hands what it hit to
## the payload the ability system configured on it.
##
## Payloads are plugin GameplayEffects (damage, statuses, ...), so this scene
## stays dumb: it only knows how to fly and who fired it. It replaces the
## plugin's ProjectileBase, which is 3D only (CharacterBody3D + Transform3D).
##
## Collision layers: 1 = world/walls, 2 = characters, 3 = projectiles.
## The projectile scans 1 and 2, and ignores whoever fired it.

signal travelled(distance: float)
signal impacted(target: Node)

## Component name the plugin looks damage up through; entities without it (walls,
## scenery) are simply not damageable.
const VITAL_COMPONENT: String = "GameplayVitalAttributeComponent"

@export var speed: float = 520.0
@export var max_distance: float = 480.0

var direction: Vector2 = Vector2.RIGHT
var distance_travelled: float = 0.0
## Effects applied to whatever it hits; filled in by the ability that fired it.
var payload_effects: Array[GameplayEffect] = []
## Field spawned where it stops (impact or end of flight) - the bomb's blast.
var impact_field: MagicFieldData2D = null
## Who fired it: the effect instigator, and never a valid target.
var instigator: Node = null

@onready var _body: Polygon2D = $Body
@onready var _collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_fit_body_to_collision_shape()
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)

## Applies the launch parameters (payload is set separately by the ability).
func launch(new_direction: Vector2, launch_speed: float, range_distance: float) -> void:
	direction = new_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	speed = launch_speed
	max_distance = range_distance
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	distance_travelled += step
	travelled.emit(distance_travelled)
	if distance_travelled >= max_distance:
		_detonate(global_position)
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body == instigator:
		return
	_deliver_payload(body)
	_detonate(global_position)
	impacted.emit(body)
	queue_free()

## Spawns the payload field (if any) at `position`.
func _detonate(position: Vector2) -> void:
	if impact_field == null or not is_instance_valid(impact_field.field_scene):
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var field: Node = impact_field.field_scene.instantiate()
	parent.add_child(field)
	if field.has_method("start"):
		field.start(impact_field, instigator, position)

func _deliver_payload(target: Node) -> void:
	if payload_effects.is_empty() or not _is_damageable(target):
		return
	var context := {"source_node": self}
	for effect in payload_effects:
		if is_instance_valid(effect):
			# Clone per hit: effects keep runtime state.
			(effect.duplicate(true) as GameplayEffect).apply(target, instigator, context)

func _is_damageable(target: Node) -> bool:
	return target.has_method("get_gameplay_vital_attribute_component") or target.has_node(VITAL_COMPONENT)

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
