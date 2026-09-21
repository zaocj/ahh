class_name HeroCards
extends Control
## The character roster of the select screen: five cards, drawn procedurally like the
## rest of the placeholder UI, with a plain hit test.
##
## It owns no match state - it reports which card was chosen and draws the selection.

signal card_chosen(index: int)

const CARD_SIZE: Vector2 = Vector2(196.0, 300.0)
const CARD_GAP: float = 20.0
const PADDING: float = 16.0
const CARD_FILL: Color = Color(0.10, 0.12, 0.18, 0.95)
const CARD_BORDER: Color = Color(0.45, 0.5, 0.62, 0.8)
const SELECTED_BORDER: Color = Color(1.0, 0.94, 0.7, 1.0)
const NAME_COLOR: Color = Color(0.95, 0.96, 1.0)
const MUTED: Color = Color(0.68, 0.72, 0.8)

var _heroes: Array[HeroData] = []
var _selected: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func setup(heroes: Array[HeroData]) -> void:
	_heroes = heroes
	_selected = 0 if heroes.is_empty() else 0
	queue_redraw()

func heroes() -> Array[HeroData]:
	return _heroes

func selected_index() -> int:
	return _selected

func selected_hero() -> HeroData:
	if _selected < 0 or _selected >= _heroes.size():
		return null
	return _heroes[_selected]

func select(index: int) -> void:
	if index < 0 or index >= _heroes.size() or index == _selected:
		return
	_selected = index
	queue_redraw()
	card_chosen.emit(index)

func _gui_input(event: InputEvent) -> void:
	var position := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		position = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
	if position == Vector2.INF:
		return
	accept_event()
	select(_index_at(position))

func _index_at(position: Vector2) -> int:
	for index in _heroes.size():
		if _card_rect(index).has_point(position):
			return index
	return -1

## Cards are laid out in a centred row; the screen uses this to size the node.
func row_size(count: int) -> Vector2:
	if count <= 0:
		return Vector2.ZERO
	return Vector2(count * CARD_SIZE.x + (count - 1) * CARD_GAP, CARD_SIZE.y)

func _card_rect(index: int) -> Rect2:
	var total := row_size(_heroes.size())
	var origin := (size - total) * 0.5
	return Rect2(origin + Vector2(index * (CARD_SIZE.x + CARD_GAP), 0.0), CARD_SIZE)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for index in _heroes.size():
		var hero := _heroes[index]
		var rect := _card_rect(index)
		draw_rect(rect, CARD_FILL)
		# Colour band: the hero's own colour, so the card matches the unit in game.
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 54.0)), Color(hero.color, 0.85))
		var border := SELECTED_BORDER if index == _selected else CARD_BORDER
		draw_rect(rect, border, false, 4.0 if index == _selected else 2.0)

		var x := rect.position.x + PADDING
		var width := rect.size.x - PADDING * 2.0
		draw_string(font, rect.position + Vector2(x - rect.position.x, 88.0), hero.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, width, 26, NAME_COLOR)
		draw_string(font, rect.position + Vector2(x - rect.position.x, 118.0), hero.skill_name,
			HORIZONTAL_ALIGNMENT_LEFT, width, 17, Color(hero.color, 0.95))
		draw_multiline_string(font, rect.position + Vector2(x - rect.position.x, 150.0),
			hero.description, HORIZONTAL_ALIGNMENT_LEFT, width, 15, 3, MUTED)
		if index == _selected:
			draw_string(font, rect.position + Vector2(x - rect.position.x, rect.size.y - 18.0),
				"SELECTED", HORIZONTAL_ALIGNMENT_LEFT, width, 14, SELECTED_BORDER)
