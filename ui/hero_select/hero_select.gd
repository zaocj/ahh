extends Control
## Character select: pick one of the five heroes, then start the 3v3.
##
## The pick is handed to the match scene through `MatchConfig` (a static holder: the
## lobby and the match are different scenes). Presentation only - it never touches
## units or abilities.

const MATCH_SCENE: String = "res://main/main.tscn"
const LOBBY_SCENE: String = "res://ui/lobby/lobby.tscn"
const ROSTER: String = "res://heroes/roster.tres"

@onready var _cards: HeroCards = $Cards
@onready var _start: ActionButton = $Start
@onready var _back: ActionButton = $Back
@onready var _status: Label = $Status

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_start.pressed.connect(_on_start_pressed)
	_back.pressed.connect(_on_back_pressed)
	_cards.card_chosen.connect(_on_card_chosen)
	var roster := load(ROSTER) as TeamRoster
	var heroes: Array[HeroData] = [] if roster == null else roster.selectable
	_cards.setup(heroes)
	_on_card_chosen(_cards.selected_index())
	# Keep the roster row centred when the window is resized (anchors + expand).
	_cards.resized.connect(_centre_cards)
	_centre_cards()

func _centre_cards() -> void:
	var row := _cards.row_size(_cards.heroes().size())
	_cards.size = Vector2(maxf(row.x, 10.0), maxf(row.y, 10.0))
	_cards.position = (size - _cards.size) * 0.5
	_cards.position.y = 150.0
	_cards.queue_redraw()

func _on_card_chosen(index: int) -> void:
	var hero := _cards.selected_hero()
	if hero == null:
		return
	_status.text = "%s - %s" % [hero.display_name, hero.skill_name]

func _on_start_pressed() -> void:
	var hero := _cards.selected_hero()
	if hero == null:
		return
	MatchConfig.selected_hero = hero
	get_tree().change_scene_to_file(MATCH_SCENE)

func _on_back_pressed() -> void:
	MatchConfig.clear()
	get_tree().change_scene_to_file(LOBBY_SCENE)
