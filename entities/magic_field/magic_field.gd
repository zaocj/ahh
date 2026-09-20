extends Node2D
class_name MagicField2D
## Ground zone that ticks plugin effects on everything of `target_group` inside
## its radius. Backs both the lasting 魔阵 and the bomb blast.
##
## Gameplay only: it resolves targets and hands them to plugin GameplayEffects;
## the ring it draws is presentation.

signal ticked(targets: Array[Node])

const TICK_EPSILON: float = 0.001

var data: MagicFieldData2D = null
var instigator: Node = null

var _remaining: float = 0.0
var _tick_timer: float = 0.0
var _radius: float = 0.0
var _color: Color = Color.WHITE

func _ready() -> void:
	z_index = -1  # ground decor: under characters, above the terrain backdrop
	set_process(false)

## Starts the field; expects the node to be in the tree already.
func start(field_data: MagicFieldData2D, source: Node, position: Vector2) -> void:
	data = field_data
	instigator = source
	global_position = position
	_radius = data.radius
	_color = data.color
	_remaining = maxf(0.0, data.duration)
	_tick_timer = 0.0
	queue_redraw()
	set_process(true)
	if data.tick_interval <= 0.0:
		_apply_payload()
		_tick_timer = -1.0  # single shot

func _process(delta: float) -> void:
	if data == null:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
		return
	if _tick_timer >= 0.0:
		_tick_timer -= delta
		if _tick_timer <= TICK_EPSILON:
			_apply_payload()
			if data.tick_interval <= 0.0:
				_tick_timer = -1.0
			else:
				_tick_timer = data.tick_interval

## Targets of `target_group` inside the radius.
func targets_inside() -> Array[Node]:
	var found: Array[Node] = []
	if data == null or not is_inside_tree():
		return found
	for node in get_tree().get_nodes_in_group(data.target_group):
		var target := node as Node2D
		if target == null or not is_instance_valid(target):
			continue
		if global_position.distance_to(target.global_position) <= _radius:
			found.append(target)
	return found

func _apply_payload() -> void:
	if data == null or data.payload_effects.is_empty():
		return
	var targets := targets_inside()
	for target in targets:
		for effect in data.payload_effects:
			if is_instance_valid(effect):
				# Clone per target: effects keep runtime state.
				(effect.duplicate(true) as GameplayEffect).apply(target, instigator, {"source_node": self})
	ticked.emit(targets)

func _draw() -> void:
	draw_circle(Vector2.ZERO, _radius, _color)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, Color(_color.r, _color.g, _color.b, 0.9), 3.0, true)
