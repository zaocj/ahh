class_name Enemy
extends CharacterBody2D
## Chase enemy: walks towards the closest node of `target_group` and stops at
## `stop_distance`, so it does not shove itself into its target.
##
## Health comes from the ability system plugin: a GameplayVitalAttributeComponent
## with a `health` vital. Damage therefore arrives through plugin effects
## (GE_ApplyDamage as a projectile payload) and this script only reacts to the
## component's signals with visuals.

@export var speed: float = 170.0
## Distance to the target at which the enemy stops walking.
@export var stop_distance: float = 30.0
## Group the chase target is looked up in; the player joins it in player.tscn.
@export var target_group: StringName = &"players"
@export var hit_flash_time: float = 0.1

@export_group("Ability System")
## Attributes and vitals for the plugin component; the vital's max comes from the
## `max_health` attribute.
@export var stats: StatBlock2D

const HEALTH_VITAL: StringName = &"health"
## Status that stops the enemy from walking (applied by the frost skill).
const FREEZE_STATUS: StringName = &"frozen"
const FROZEN_COLOR: Color = Color(0.45, 0.72, 0.98)
const BAR_SIZE: Vector2 = Vector2(34.0, 5.0)
const BAR_OFFSET: Vector2 = Vector2(0.0, -30.0)
const BAR_BACK: Color = Color(0.05, 0.06, 0.10, 0.85)
const BAR_FILL: Color = Color(0.95, 0.35, 0.35)
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)

## Last direction the enemy walked in (kept for symmetry with the player).
var facing: Vector2 = Vector2.DOWN
## Current chase target; re-resolved lazily when it is gone.
var target: Node2D = null

@onready var _vitals: GameplayVitalAttributeComponent = $GameplayVitalAttributeComponent
@onready var _statuses: GameplayStatusComponent = $GameplayStatusComponent
@onready var _body: Polygon2D = $Body

var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_base_color = _body.color
	if stats != null:
		_vitals.initialize(stats.attribute_sets, stats.vitals)
	_vitals.vital_value_changed.connect(_on_vital_changed)
	_vitals.vital_depleted.connect(_on_vital_depleted)
	_statuses.status_applied.connect(_on_status_applied)
	_statuses.status_removed.connect(_on_status_removed)
	# The vital's own signals carry the exact numbers, which is what hit feedback needs.
	var vital := health()
	if vital != null:
		vital.damage_applied.connect(_on_damage_applied)
		vital.health_depleted.connect(_on_health_depleted)

func _physics_process(_delta: float) -> void:
	# Frozen by the frost skill: rooted, but still a valid damage target.
	if is_frozen():
		velocity = Vector2.ZERO
		return

	var offset := target_offset()
	velocity = Vector2.ZERO
	if offset.length() > stop_distance:
		velocity = offset.normalized() * speed
		facing = velocity.normalized()
	move_and_slide()

## True while the frost status is on: the enemy cannot walk.
func is_frozen() -> bool:
	return _statuses.has_status(FREEZE_STATUS)

## Entity contract used by MatchDirector: is this enemy still in the fight?
## (A defeated enemy frees itself in `_on_vital_depleted`.)
func is_alive() -> bool:
	var vital := health()
	return vital != null and vital.is_alive

## Plugin interface hook, same convention as the player: lets the ability system
## (and the AI router) find this entity's ability component by name.
func get_gameplay_ability_component() -> GameplayAbilityComponent:
	return $Abilities

## The plugin vital holding this enemy's hit points.
func health() -> GameplayVital:
	return _vitals.get_vital(HEALTH_VITAL)

func health_ratio() -> float:
	var vital := health()
	return 0.0 if vital == null else vital.get_percent()

## Vector from the enemy to its target; ZERO when nothing is chaseable.
func target_offset() -> Vector2:
	if not is_instance_valid(target):
		target = Targets.nearest(self, target_group)
	if target == null:
		return Vector2.ZERO
	return target.global_position - global_position

func _on_vital_changed(vital_id: StringName, _current: float, _max: float, _percent: float, is_regen: bool) -> void:
	if vital_id != HEALTH_VITAL or is_regen:
		return
	queue_redraw()
	var vital := health()
	if vital != null and vital.is_alive:
		_flash()

func _on_status_applied(status_id: StringName, _instance: GameplayStatusInstance) -> void:
	if status_id == FREEZE_STATUS:
		_body.color = FROZEN_COLOR
		queue_redraw()

func _on_status_removed(status_id: StringName) -> void:
	if status_id == FREEZE_STATUS:
		_body.color = _base_color
		queue_redraw()

func _on_vital_depleted(vital_id: StringName) -> void:
	if vital_id == HEALTH_VITAL:
		queue_free()

func _on_damage_applied(damage_info: GameplayDamageInfo, final_damage: float) -> void:
	CombatEvents.report_damage(self, final_damage, damage_info.instigator)

func _on_health_depleted(instigator: Node) -> void:
	CombatEvents.report_death(self, instigator)

func _flash() -> void:
	if is_frozen():
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
