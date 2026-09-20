class_name SkillDrawer
extends Control
## Slide-out drawer that swaps the ability of one slot.
##
## Contents come from the loadout inventory through the router, so adding a skill
## to the inventory is enough to make it appear here. Presentation only: it asks
## the router to equip and reports the selection.

signal ability_chosen(ability_id: StringName)

## Slot this drawer replaces.
@export var slot: int = 0
@export var row_height: float = 56.0
@export var slide_time: float = 0.18

var _router: AbilityInputRouter = null
var _rows: Array[GameplayAbilityDefinition] = []
var _open: bool = false
var _tween: Tween = null

const PADDING: float = 10.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	# Start off-screen right; toggle() slides it in.
	offset_left = size.x + PADDING
	offset_right = size.x * 2.0 + PADDING

## Wires the drawer to a router and fills it with that router's inventory.
func setup(router: AbilityInputRouter) -> void:
	_router = router
	refresh()

func refresh() -> void:
	_rows.clear()
	if _router != null:
		for ability in _router.inventory():
			if is_instance_valid(ability):
				_rows.append(ability)
	queue_redraw()

func is_open() -> bool:
	return _open

func toggle() -> void:
	_open = not _open
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var closed_left := size.x + PADDING
	var open_left := -size.x - PADDING
	_tween.tween_property(self, "offset_left", open_left if _open else closed_left, slide_time)
	_tween.parallel().tween_property(self, "offset_right", open_left + size.x if _open else closed_left + size.x, slide_time)

func _gui_input(event: InputEvent) -> void:
	var position := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		position = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
	if position == Vector2.INF:
		return
	accept_event()
	var index := _row_at(position)
	if index < 0 or _router == null:
		return
	var ability := _rows[index]
	if _router.equip(slot, ability.ability_id):
		ability_chosen.emit(ability.ability_id)
		queue_redraw()

func _row_at(position: Vector2) -> int:
	if position.x < 0.0 or position.x > size.x:
		return -1
	var index := int((position.y - PADDING) / row_height)
	if index < 0 or index >= _rows.size():
		return -1
	return index

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.12, 0.92))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.62, 0.75, 0.85), false, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(0.0, PADDING + 18.0),
		"SKILL SLOT %d" % (slot + 1), HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1, 1, 1, 0.75))

	var equipped := "" if _router == null else String(_router.ability_id(slot))
	for i in _rows.size():
		var ability := _rows[i]
		var rect := Rect2(Vector2(PADDING, PADDING + 28.0 + row_height * float(i)),
			Vector2(size.x - PADDING * 2.0, row_height - 8.0))
		var is_equipped := String(ability.ability_id) == equipped
		var tint := Color(0.35, 0.85, 0.55, 0.9) if is_equipped else Color(0.55, 0.62, 0.75, 0.9)
		draw_rect(rect, Color(tint, 0.22 if is_equipped else 0.10))
		draw_rect(rect, tint, false, 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(12.0, 24.0), ability.ability_name,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 20, Color(1, 1, 1, 0.95))
		var cooldown := _cooldown_text(ability)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(12.0, 42.0), cooldown,
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 24.0, 14, Color(1, 1, 1, 0.6))
		if is_equipped:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 70.0, 24.0), "EQUIPPED",
				HORIZONTAL_ALIGNMENT_LEFT, 70.0, 13, Color(0.45, 0.95, 0.65, 0.95))

func _cooldown_text(ability: GameplayAbilityDefinition) -> String:
	for feature in ability.features:
		var cooldown := feature as CooldownFeature
		if cooldown != null:
			return "cooldown %.1fs" % cooldown.cooldown_duration
	return "-"
