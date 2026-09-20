extends Node
class_name AbilityInputRouter
## Bridges the on-screen ability buttons to the plugin's ability lifecycle.
##
## The plugin expects the game to drive its preview: press starts one (indicator
## on), drag feeds an aim direction, release confirms and casts. That is all this
## node does - cooldowns, execution and indicators stay inside the plugin.

signal ability_activated(slot: int, ability_id: StringName)

## Slot order must match the HUD buttons; slot 0 is the first button.
@export var loadout: AbilityLoadout2D
## Drag must leave this dead zone before it overrides the skill's default aim,
## so a tap always casts along the default (auto-aim) direction.
@export var aim_dead_zone: float = 12.0

var _pressed_slot: int = -1
var _previewing_slot: int = -1
var _press_position: Vector2 = Vector2.ZERO
var _aim_direction: Vector2 = Vector2.ZERO
var _component: GameplayAbilityComponent = null

func _ready() -> void:
	# The component sits next to us on the caster; the plugin's own lookup helper
	# also accepts an interface method.
	var caster := get_parent()
	if caster != null:
		_component = GameplayAbilitySystem.get_component_by_interface(caster, "GameplayAbilityComponent") as GameplayAbilityComponent
	if _component != null and loadout != null:
		for ability in loadout.abilities:
			if is_instance_valid(ability):
				_component.learn_ability(ability)

func _process(delta: float) -> void:
	if _previewing_slot >= 0 and _component != null:
		# Keeps the indicator on the caster while it moves, and carries the aim.
		_component.update_targeting(delta, {"aim_direction": _aim_direction})

## Slot helpers, used by the HUD.
func ability_definition(slot: int) -> GameplayAbilityDefinition:
	if loadout == null or slot < 0 or slot >= loadout.abilities.size():
		return null
	return loadout.abilities[slot]

func ability_id(slot: int) -> StringName:
	var ability := ability_definition(slot)
	return &"" if ability == null else ability.ability_id

func slot_count() -> int:
	return 0 if loadout == null else loadout.abilities.size()

func ability_instance(slot: int) -> GameplayAbilityInstance:
	if _component == null:
		return null
	return _component.get_ability_instance(ability_id(slot))

func is_ready(slot: int) -> bool:
	return _component != null and _component.can_activate_ability(ability_id(slot))

## 0.0 = ready, 1.0 = just went on cooldown (drives the button pie).
func cooldown_ratio(slot: int) -> float:
	var instance := ability_instance(slot)
	if instance == null:
		return 0.0
	var cooldown := instance.get_feature("CooldownFeature") as CooldownFeature
	return 0.0 if cooldown == null else cooldown.get_cooldown_progress(instance)

#region ========== pointer events (from ui/hud/skill_button.gd) ==========
func press(slot: int, position: Vector2) -> void:
	if _component == null:
		return
	var id := ability_id(slot)
	if id.is_empty() or not _component.can_activate_ability(id):
		return

	_pressed_slot = slot
	_previewing_slot = -1
	_press_position = position
	_aim_direction = Vector2.ZERO
	# Returns non-null only when the ability has a preview strategy; instant
	# abilities stay pending and fire on release.
	if _component.request_ability_preview(id) != null:
		_previewing_slot = slot

func drag(slot: int, position: Vector2) -> void:
	if slot != _pressed_slot:
		return
	var offset := position - _press_position
	if offset.length() < aim_dead_zone:
		return
	_aim_direction = offset.normalized()

func release(slot: int, position: Vector2) -> void:
	if slot != _pressed_slot or _component == null:
		return
	drag(slot, position)
	var id := ability_id(slot)

	# `targets` keeps the plugin's AbilityNodeBase happy for abilities without a
	# preview strategy (it assigns context[target_key] into a typed array).
	var targets: Array[Node] = []
	var context := {"target_direction": _aim_direction, "targets": targets}
	if _previewing_slot == slot:
		# Confirm first: the strategy answers with the default direction when the
		# player never dragged (that is the tap / auto-aim path).
		context = _component.confirm_targeting()
		_component.cancel_ability_preview(id)

	_pressed_slot = -1
	_previewing_slot = -1
	_aim_direction = Vector2.ZERO
	if _component.try_activate_ability(id, context):
		ability_activated.emit(slot, id)

## Pointer went away without a release (touch cancelled by the OS).
func cancel_aim() -> void:
	if _component != null and _previewing_slot >= 0:
		_component.cancel_ability_preview(ability_id(_previewing_slot))
	_pressed_slot = -1
	_previewing_slot = -1
	_aim_direction = Vector2.ZERO
#endregion
