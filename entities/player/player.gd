class_name Player
extends CharacterBody2D
## Top-down arena player: a colored square driven by the named movement actions
## or by the on-screen joystick.
##
## The body runs in floating motion mode because the arena has no gravity and no
## floor concept: every collision is a wall.

signal moved(direction: Vector2)
signal blocked(direction: Vector2)
## Emitted once when the health vital runs out; MatchDirector turns it into a loss.
signal died

const HEALTH_VITAL: StringName = &"health"
const BAR_SIZE: Vector2 = Vector2(34.0, 5.0)
const BAR_OFFSET: Vector2 = Vector2(0.0, -30.0)
const BAR_BACK: Color = Color(0.05, 0.06, 0.10, 0.85)
const BAR_FILL: Color = Color(0.35, 0.9, 0.6)
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)
## Tint of a defeated player: it stays in the world (the camera is on it).
const DEAD_COLOR: Color = Color(0.42, 0.45, 0.52)

@export var speed: float = 220.0
@export var acceleration: float = 2600.0
@export var friction: float = 3200.0
@export var hit_flash_time: float = 0.1

@export_group("Ability System")
## Attributes and vitals for the plugin component (health, so healing works).
@export var stats: StatBlock2D

## Direction pushed by the on-screen joystick; combined with the key actions.
var joystick_input: Vector2 = Vector2.ZERO

## Last direction the player moved/faced. Skills use it as the default cast
## direction (taps fire straight ahead).
var facing: Vector2 = Vector2.RIGHT

var _dash_direction: Vector2 = Vector2.ZERO
var _dash_speed: float = 0.0
var _dash_remaining: float = 0.0
var _dash_active: bool = false

## True while the player can still act; false from the moment health hits 0.
var _alive: bool = true
## True while the player pushes into a wall during the latest physics step.
var is_blocked: bool = false

@onready var _body: Polygon2D = $Body
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _vitals: GameplayVitalAttributeComponent = $GameplayVitalAttributeComponent

var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_fit_body_to_collision_shape()
	_base_color = _body.color
	if stats != null:
		_vitals.initialize(stats.attribute_sets, stats.vitals)
	_vitals.vital_value_changed.connect(_on_vital_changed)
	_vitals.vital_depleted.connect(_on_vital_depleted)
	# The vital's own signals carry the exact numbers (the component's only say what
	# the value is now), so combat feedback is reported from here.
	var vital := health()
	if vital != null:
		vital.damage_applied.connect(_on_damage_applied)
		vital.health_depleted.connect(_on_health_depleted)

## Plugin interface hook: lets the ability system (and effects) find this
## entity's ability component without knowing the node name.
func get_gameplay_ability_component() -> GameplayAbilityComponent:
	return $Abilities

## The plugin vital holding this player's hit points.
func health() -> GameplayVital:
	return _vitals.get_vital(HEALTH_VITAL)

func health_ratio() -> float:
	var vital := health()
	return 0.0 if vital == null else vital.get_percent()

## Entity contract used by MatchDirector (and any future AI): is this thing still
## in the fight?
func is_alive() -> bool:
	return _alive and health_ratio() > 0.0

func _on_vital_changed(vital_id: StringName, _current: float, _max: float, _percent: float, is_regen: bool) -> void:
	if vital_id != HEALTH_VITAL or is_regen or not _alive:
		return
	queue_redraw()
	_flash()

## Health hit 0: stop acting, keep the node (the camera rides on it) and let the
## match director decide what that means for the match.
func _on_vital_depleted(vital_id: StringName) -> void:
	if vital_id != HEALTH_VITAL or not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	_dash_active = false
	_dash_remaining = 0.0
	joystick_input = Vector2.ZERO
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_body.color = DEAD_COLOR
	# Casting is blocked by AbilityInputRouter (it asks us is_alive()). The plugin's
	# own disable_ability() cannot do it: GameplayAbilityInstance.disabled is a
	# getter over the shared definition, so writing it has no effect at all
	# (AGENTS.md pitfall 16).
	queue_redraw()
	died.emit()

func _on_damage_applied(damage_info: GameplayDamageInfo, final_damage: float) -> void:
	CombatEvents.report_damage(self, final_damage, damage_info.instigator)

func _on_health_depleted(instigator: Node) -> void:
	CombatEvents.report_death(self, instigator)

func _flash() -> void:
	if not _alive:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_body.color = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_body, "color", _base_color, hit_flash_time)

func _draw() -> void:
	var origin := BAR_OFFSET - Vector2(BAR_SIZE.x * 0.5, 0.0)
	draw_rect(Rect2(origin - Vector2(1.0, 1.0), BAR_SIZE + Vector2(2.0, 2.0)), BAR_BACK)
	var ratio := health_ratio()
	if ratio > 0.0:
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * ratio, BAR_SIZE.y)), BAR_FILL)

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
	if not _alive:
		velocity = Vector2.ZERO
		return
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
