class_name SkillController
extends Node
## Owns a caster's skill slots: cooldowns, aiming, casting.
##
## Input comes from ui/hud/skill_button.gd as three calls - press / drag /
## release. A short tap casts straight ahead, holding shows the skill's own
## indicator to aim. Casting itself is delegated to SkillExecutor.

signal skill_casted(slot: int, skill: SkillData)
signal cooldown_changed(slot: int, remaining: float, total: float)

## One skill per slot, in the same order as the HUD buttons.
@export var skills: Array[SkillData] = []
## Press shorter than this (and barely dragged) counts as a tap.
@export var tap_max_duration: float = 0.18
## Dragging further than this counts as aiming, never as a tap.
@export var tap_max_drag: float = 24.0
## Drag must leave this dead zone before it overrides the caster's facing.
@export var aim_dead_zone: float = 12.0

@onready var _caster: Node2D = get_parent() as Node2D
@onready var _indicator: SkillIndicator = get_node_or_null("Indicator") as SkillIndicator

var _cooldown_left: PackedFloat64Array = PackedFloat64Array()
var _aim_slot: int = -1
var _aim_time: float = 0.0
var _aim_press_position: Vector2 = Vector2.ZERO
var _aim_dragged: float = 0.0
var _aim_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	_cooldown_left.resize(skills.size())
	_cooldown_left.fill(0.0)

func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	if _aim_slot >= 0:
		_aim_time += delta
		_update_indicator()

## ---------------------------------------------------------------- slot queries

func skill_count() -> int:
	return skills.size()

func get_skill(slot: int) -> SkillData:
	return skills[slot] if _is_valid_slot(slot) else null

func is_ready(slot: int) -> bool:
	return _is_valid_slot(slot) and _cooldown_left[slot] <= 0.0

func cooldown_left(slot: int) -> float:
	return _cooldown_left[slot] if _is_valid_slot(slot) else 0.0

## 1.0 right after casting, 0.0 when ready again.
func cooldown_ratio(slot: int) -> float:
	var skill := get_skill(slot)
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_left[slot] / skill.cooldown, 0.0, 1.0)

## -------------------------------------------------------------------- aiming

## Start aiming with `position` (pixels relative to the button centre).
func press(slot: int, position: Vector2) -> void:
	if not is_ready(slot):
		return
	_aim_slot = slot
	_aim_time = 0.0
	_aim_press_position = position
	_aim_dragged = 0.0
	_aim_direction = facing_direction()
	_update_indicator()

func drag(slot: int, position: Vector2) -> void:
	if slot != _aim_slot:
		return
	var offset := position - _aim_press_position
	if offset.length() < aim_dead_zone:
		return
	_aim_dragged = maxf(_aim_dragged, offset.length())
	_aim_direction = offset.normalized()

func release(slot: int, position: Vector2) -> void:
	if slot != _aim_slot:
		return
	drag(slot, position)
	var direction := _aim_direction
	if _aim_time <= tap_max_duration and _aim_dragged <= tap_max_drag:
		direction = facing_direction()
	_end_aim()
	cast(slot, direction)

## Aborts aiming without casting (pointer stolen or touch cancelled by the OS).
func cancel_aim() -> void:
	_end_aim()

## -------------------------------------------------------------------- casting

## Casts `slot` towards `direction` (falls back to the caster's facing).
func cast(slot: int, direction: Vector2) -> bool:
	var skill := get_skill(slot)
	if skill == null or not is_ready(slot) or _caster == null:
		return false
	if direction == Vector2.ZERO:
		direction = facing_direction()
	direction = direction.normalized()
	_set_facing(direction)
	_cooldown_left[slot] = skill.cooldown

	var context := SkillContext.new()
	context.caster = _caster
	context.origin = _caster.global_position
	context.direction = direction
	context.world = _caster.get_parent()

	SkillExecutor.execute(skill, context)
	cooldown_changed.emit(slot, _cooldown_left[slot], skill.cooldown)
	skill_casted.emit(slot, skill)
	return true

## The caster's facing, used as the cast direction for taps and as the initial
## aim direction while holding.
func facing_direction() -> Vector2:
	if _caster != null and "facing" in _caster:
		var facing: Vector2 = _caster.facing
		if facing != Vector2.ZERO:
			return facing.normalized()
	return Vector2.RIGHT

## -------------------------------------------------------------------- internals

func _end_aim() -> void:
	_aim_slot = -1
	_aim_time = 0.0
	_aim_dragged = 0.0
	if _indicator != null:
		_indicator.hide_indicator()

func _update_indicator() -> void:
	var skill := get_skill(_aim_slot)
	if _indicator == null or skill == null or _caster == null:
		return
	_indicator.global_position = _caster.global_position
	_indicator.set_direction(_aim_direction)
	_indicator.show_indicator(skill.indicator)

func _set_facing(direction: Vector2) -> void:
	if _caster != null and "facing" in _caster:
		_caster.facing = direction

func _tick_cooldowns(delta: float) -> void:
	for slot in _cooldown_left.size():
		if _cooldown_left[slot] <= 0.0:
			continue
		_cooldown_left[slot] = maxf(_cooldown_left[slot] - delta, 0.0)
		var total: float = skills[slot].cooldown if skills[slot] != null else 0.0
		cooldown_changed.emit(slot, _cooldown_left[slot], total)

func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < skills.size() and skills[slot] != null
