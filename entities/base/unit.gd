class_name Unit
extends CharacterBody2D
## One combat unit: the single reusable entity for both teams and for human or AI
## control.
##
## It replaces the old Player/Enemy pair, which differed only in where the movement
## comes from (keyboard+joystick vs chase) and in cosmetics - both are now data
## (`controller`, `team`, `hero`). A match instantiates this scene once per seat.
##
## Entity contract used by the rest of the game:
##   facing, dash(direction, distance, duration), is_dashing()
##   is_alive(), health(), health_ratio()
##   team, hostile_group() - the group AI and auto-aim look for
##   get_gameplay_ability_component()
##
## Teams: a unit joins `Teams.group_of(team)` (targeting / survivor counting) and
## `units`; the local player's unit also joins `players` (what the camera, the HUD
## and the "I got hit" audio key on). On death the unit stops colliding and leaves
## its team group, so nothing targets or is blocked by a corpse.

enum Controller {
	HUMAN, ## Keyboard actions or the on-screen joystick.
	AI, ## Walks at the nearest hostile unit and lets its ability routers fire.
}

signal moved(direction: Vector2)
signal blocked(direction: Vector2)
## Emitted once when the health vital runs out.
signal died

const HEALTH_VITAL: StringName = &"health"
const UNITS_GROUP: StringName = &"units"
const HUMAN_GROUP: StringName = &"players"
const BAR_SIZE: Vector2 = Vector2(34.0, 5.0)
const BAR_OFFSET: Vector2 = Vector2(0.0, -30.0)
const BAR_BACK: Color = Color(0.05, 0.06, 0.10, 0.85)
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)
## Tint of a defeated unit: it stays in the world (scores, and the camera of the
## local player), but it no longer collides or gets targeted.
const DEAD_COLOR: Color = Color(0.42, 0.45, 0.52)
## Status that roots the unit (frost).
const FREEZE_STATUS: StringName = &"frozen"
const FROZEN_COLOR: Color = Color(0.45, 0.72, 0.98)

@export_group("Control")
@export var controller: Controller = Controller.AI
@export var team: int = Teams.Id.RED
## Character data: look, stats and skill loadout. Assigned by the spawner.
@export var hero: HeroData

@export_group("Movement")
@export var speed: float = 200.0
@export var acceleration: float = 2600.0
@export var friction: float = 3200.0
## AI: distance to the target at which it stops walking.
@export var stop_distance: float = 190.0
@export var hit_flash_time: float = 0.1

@export_group("Ability System")
## Attributes and vitals for the plugin component; `hero.stats` wins when set.
@export var stats: StatBlock2D

## Direction pushed by the on-screen joystick (human units only).
var joystick_input: Vector2 = Vector2.ZERO
## Last direction the unit moved/faced; skills use it as their fallback aim.
var facing: Vector2 = Vector2.RIGHT
## True while the unit pushes into a wall during the latest physics step.
var is_blocked: bool = false

var _alive: bool = true
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_speed: float = 0.0
var _dash_remaining: float = 0.0
var _dash_active: bool = false
var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null

@onready var _body: Polygon2D = $Body
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _vitals: GameplayVitalAttributeComponent = $GameplayVitalAttributeComponent
@onready var _statuses: GameplayStatusComponent = $GameplayStatusComponent

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_fit_body_to_collision_shape()
	add_to_group(UNITS_GROUP)
	add_to_group(Teams.group_of(team))
	if is_human():
		add_to_group(HUMAN_GROUP)
	_set_team_color()

	var block := stats
	if hero != null and hero.stats != null:
		block = hero.stats
	if block != null:
		_vitals.initialize(block.attribute_sets, block.vitals)
	_vitals.vital_value_changed.connect(_on_vital_changed)
	_vitals.vital_depleted.connect(_on_vital_depleted)
	_statuses.status_applied.connect(_on_status_applied)
	_statuses.status_removed.connect(_on_status_removed)
	# The vital's own signals carry the exact numbers, which is what feedback and the
	# scoreboard need (the component's only say what the value is now).
	var vital := health()
	if vital != null:
		vital.damage_applied.connect(_on_damage_applied)
		vital.health_depleted.connect(_on_health_depleted)

## Called by the spawner *before* the unit enters the tree (its `_ready` needs it).
func configure(new_hero: HeroData, new_team: int, new_controller: Controller) -> void:
	hero = new_hero
	team = new_team
	controller = new_controller
	if is_inside_tree():
		_set_team_color()

func is_human() -> bool:
	return controller == Controller.HUMAN

## True when this unit is in the group the HUD/camera/audio key on (the local player).
func human_group_only() -> bool:
	return is_in_group(HUMAN_GROUP)

## Plugin interface hook: lets the ability system (and the routers) find this
## entity's ability component without knowing the node name.
func get_gameplay_ability_component() -> GameplayAbilityComponent:
	return $Abilities

## Group the opposing team is in: what AI chases and what auto-aim looks for.
func hostile_group() -> StringName:
	return Teams.enemy_group_of(team)

func health() -> GameplayVital:
	return _vitals.get_vital(HEALTH_VITAL)

func health_ratio() -> float:
	var vital := health()
	return 0.0 if vital == null else vital.get_percent()

## True while the unit can still act.
func is_alive() -> bool:
	return _alive and health_ratio() > 0.0

func is_frozen() -> bool:
	return _statuses.has_status(FREEZE_STATUS)

func display_name() -> String:
	return hero.display_name if hero != null else name

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
		direction = _wanted_direction()
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

	# A dash ends without inertia, otherwise the leftover speed slides the unit well
	# past the configured distance.
	if was_dashing and not _dash_active:
		velocity = Vector2.ZERO

	is_blocked = direction != Vector2.ZERO and is_on_wall()
	if is_blocked:
		blocked.emit(direction)

## Where the unit wants to go this step: player input or the AI's chase.
func _wanted_direction() -> Vector2:
	if is_human():
		return _input_direction()
	return _ai_direction()

## Keyboard/gamepad actions take priority unless the joystick pushes further.
func _input_direction() -> Vector2:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if joystick_input.length() > direction.length():
		direction = joystick_input
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction

## Walk at the nearest hostile unit, stopping at `stop_distance` (and standing
## still while frozen, which is the counterplay the frost skill buys).
func _ai_direction() -> Vector2:
	if is_frozen():
		return Vector2.ZERO
	var target := Targets.nearest(self, hostile_group())
	if target == null:
		return Vector2.ZERO
	var offset := target.global_position - global_position
	if offset.length() <= stop_distance:
		return Vector2.ZERO
	return offset.normalized()

## Called by GE_Dash2D: slide `distance` pixels along `direction`.
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

func _on_vital_changed(vital_id: StringName, _current: float, _max: float, _percent: float, is_regen: bool) -> void:
	if vital_id != HEALTH_VITAL or is_regen or not _alive:
		return
	queue_redraw()
	_flash()

func _on_damage_applied(damage_info: GameplayDamageInfo, final_damage: float) -> void:
	CombatEvents.report_damage(self, final_damage, damage_info.instigator)

func _on_health_depleted(instigator: Node) -> void:
	CombatEvents.report_death(self, instigator)

## Health hit 0: stop acting but stay in the world. Collisions and team membership
## go away so nothing targets or is blocked by the corpse, and the node is kept
## because the local player's camera (and the scoreboard) still refer to it.
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
	collision_layer = 0
	collision_mask = 0
	remove_from_group(Teams.group_of(team))
	queue_redraw()
	died.emit()

func _on_status_applied(status_id: StringName, _instance: GameplayStatusInstance) -> void:
	if status_id == FREEZE_STATUS:
		_body.color = FROZEN_COLOR
		queue_redraw()

func _on_status_removed(status_id: StringName) -> void:
	if status_id == FREEZE_STATUS:
		_body.color = _base_color
		queue_redraw()

func _set_team_color() -> void:
	# Team colour is the base; the hero's own colour only trims it, so sides stay
	# readable in a 6-unit fight.
	var team_color := Teams.color_of(team)
	if hero != null:
		team_color = team_color.lerp(hero.color, 0.45)
	_base_color = team_color
	if _body != null and _alive:
		_body.color = FROZEN_COLOR if is_frozen() else _base_color

func _flash() -> void:
	if not _alive or is_frozen():
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
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * ratio, BAR_SIZE.y)), Teams.color_of(team))
	# The local player's unit is the one the camera and skill buttons belong to: give
	# it a marker so it is findable in a 3v3 scrum.
	if is_human() and _alive:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.75), 2.0, true)

## The agent bridge cannot express a PackedVector2Array, so the placeholder square is
## derived from the collision shape instead of stored in the scene (AGENTS.md pitfall 2).
func _fit_body_to_collision_shape() -> void:
	var shape: Shape2D = _collision.shape
	if shape is not RectangleShape2D:
		push_warning("Unit has no RectangleShape2D; using the default square.")
	var half: Vector2 = (shape as RectangleShape2D).size * 0.5 if shape is RectangleShape2D else Vector2(14, 14)
	_body.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
