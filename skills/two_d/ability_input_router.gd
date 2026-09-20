extends Node
class_name AbilityInputRouter
## Bridges the on-screen ability buttons to the plugin's ability lifecycle.
##
## The plugin expects the game to drive its preview: press starts one (indicator
## on), drag feeds an aim direction, release confirms and casts. That is all this
## node does - cooldowns, execution and indicators stay inside the plugin.
##
## Preview ownership: the plugin only ends a preview when someone calls
## `cancel_ability_preview()`, and it keeps a single preview reference per
## component. So *this router is the only owner of the player's preview*: every
## press releases the previous one, and `_process` releases any preview left live
## with no press behind it. Without that, a missed cancel (a lost release, a
## second finger, an ability the plugin refuses to preview) leaves the indicator
## drawing on the map forever.

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
## The entity these buttons belong to; needed for the "can it act at all" check.
var _caster: Node2D = null
## Live copy of the loadout: the .tres is the starting point, swapping skills at
## runtime must not rewrite the project resource.
var _equipped: Array[GameplayAbilityDefinition] = []

func _ready() -> void:
	# The component sits next to us on the caster; the plugin's own lookup helper
	# also accepts an interface method.
	_caster = get_parent() as Node2D
	if _caster != null:
		_component = GameplayAbilitySystem.get_component_by_interface(_caster, "GameplayAbilityComponent") as GameplayAbilityComponent
	if loadout != null:
		# Per-caster copies: the plugin stores preview state on the definition's
		# strategy resource, which a .tres shares between every caster (pitfall 21).
		_equipped = loadout.private_definitions(loadout.abilities)
	if _component != null:
		for ability in _equipped:
			if is_instance_valid(ability):
				_component.learn_ability(ability)

func _process(delta: float) -> void:
	if _component == null:
		return
	if _previewing_slot >= 0:
		# Stop tracking as soon as the plugin drops the preview on its own (the
		# ability completed, another one was activated): from then on nothing is
		# aiming it, and re-confirming would hand the behavior tree a context
		# without `targets`.
		if not _component.has_targeting_ability():
			_previewing_slot = -1
			return
		# Keeps the indicator on the caster while it moves, and carries the aim.
		_component.update_targeting(delta, {"aim_direction": _aim_direction})
	elif _component.has_targeting_ability():
		# A live preview with no press behind it: nobody can confirm or aim it, so
		# release it instead of leaving its indicator on the map.
		_cancel_preview()

## Slot helpers, used by the HUD.
func ability_definition(slot: int) -> GameplayAbilityDefinition:
	if slot < 0 or slot >= _equipped.size():
		return null
	return _equipped[slot]

func ability_id(slot: int) -> StringName:
	var ability := ability_definition(slot)
	return &"" if ability == null else ability.ability_id

func slot_count() -> int:
	return _equipped.size()

## Everything that may be equipped (drawer contents).
func inventory() -> Array[GameplayAbilityDefinition]:
	return [] if loadout == null else loadout.inventory

## Swaps the ability in `slot` for the inventory ability `ability_id`.
## Returns false when it is unknown or already equipped there.
func equip(slot: int, ability_id: StringName) -> bool:
	if _component == null or loadout == null or slot < 0 or slot >= _equipped.size():
		return false
	var shared := loadout.find_in_inventory(ability_id)
	var current := ability_definition(slot)
	# Compare ids: `_equipped` holds per-caster copies, not the inventory resources.
	if shared == null or (current != null and current.ability_id == ability_id):
		return false

	# Swapping destroys the previous ability instance, which would orphan a live
	# indicator and invalidate the in-flight aim gesture; drop both.
	cancel_aim()

	var ability := loadout.private_definition(shared)
	if current != null and _component.has_ability(current.ability_id):
		_component.forget_ability(current.ability_id)
	_equipped[slot] = ability
	_component.learn_ability(ability)
	return true

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
	if _component == null or not _caster_can_act():
		return
	var id := ability_id(slot)
	if id.is_empty() or not _component.can_activate_ability(id):
		return

	# Anything still previewing belongs to an earlier press. Release it first:
	# the plugin's own "replace the preview" path is skipped for abilities it
	# refuses to preview, which would leave that indicator on the map.
	_cancel_preview()

	_pressed_slot = slot
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
	# Raw pointer offset, deliberately *not* normalized: its length is what a
	# ground-targeted skill maps to a throw distance (direction-only strategies
	# normalize it themselves). The activation context hands the behavior tree a
	# normalized direction again, so `target_direction` keeps its old contract.
	_aim_direction = offset

func release(slot: int, position: Vector2) -> void:
	if slot != _pressed_slot or _component == null:
		return
	if not _caster_can_act():
		# Died mid-aim: drop the preview instead of firing from the grave.
		cancel_aim()
		return
	drag(slot, position)
	var id := ability_id(slot)

	# Confirm before cancelling: the strategy answers with the default direction
	# when the player never dragged (that is the tap / auto-aim path). If the
	# plugin already dropped the preview, fall back to the raw aim direction.
	var aim := _aim_direction.normalized()
	var context := _activation_context(aim)
	if _previewing_slot == slot and _component.has_targeting_ability():
		# The strategy only recomputes its aim inside update(), so a drag and release
		# within one frame would confirm the *previous* aim (the tap default) - a quick
		# flick would land the skill where the preview last was, not where the player
		# let go. Push the current drag through before asking for the result.
		_component.update_targeting(0.0, {"aim_direction": _aim_direction})
		context = _activation_context(aim, _component.confirm_targeting())
	_cancel_preview()

	_pressed_slot = -1
	_aim_direction = Vector2.ZERO
	if _component.try_activate_ability(id, context):
		CombatEvents.report_cast(_caster, id)
		ability_activated.emit(slot, id)

## Pointer went away without a release (touch cancelled by the OS).
func cancel_aim() -> void:
	_cancel_preview()
	_pressed_slot = -1
	_aim_direction = Vector2.ZERO

## Releases the player's preview, whoever started it, and forgets our tracking.
func _cancel_preview() -> void:
	if _component != null:
		# No argument: cancel whatever preview is live on this caster, not just
		# the slot we happen to remember.
		_component.cancel_ability_preview()
	_previewing_slot = -1

## False once the caster is defeated. The plugin cannot express this for us:
## `GameplayAbilityInstance.disabled` is a getter over the *shared definition*,
## so `disable_ability()` silently does nothing (AGENTS.md pitfall 16).
func _caster_can_act() -> bool:
	if _caster == null:
		return true
	if _caster.has_method("is_alive"):
		return bool(_caster.call("is_alive"))
	return true

## Activation context for the behavior tree.
##
## Direction priority: a live drag is the freshest answer (the preview strategy only
## sees the aim once per frame, so the release frame can carry a newer drag), then
## whatever the preview confirmed - on a *tap* that is the skill's default
## direction (auto-aim). Overwriting it with a ZERO drag made the ability fall back
## to the caster's `facing` and fire backwards. `targets` is always present (empty)
## because AbilityNodeBase._get_target_list assigns context[target_key] into a typed
## Array[Node] and a missing key aborts that tick (AGENTS.md pitfall 10).
func _activation_context(aim_direction: Vector2, from_preview: Dictionary = {}) -> Dictionary:
	var context := from_preview.duplicate()
	if aim_direction != Vector2.ZERO or not context.has("target_direction"):
		context["target_direction"] = aim_direction
	if not context.has("targets"):
		var targets: Array[Node] = []
		context["targets"] = targets
	return context
#endregion
