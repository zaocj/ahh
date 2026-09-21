extends Control
## Start screen: the one thing to do is press START, which opens the character select.
##
## Resetting `MatchConfig` here means "play again" from the lobby always starts from
## the roster default instead of silently reusing the previous match's hero.

const HERO_SELECT_SCENE: String = "res://ui/hero_select/hero_select.tscn"

@onready var _start: ActionButton = $Start

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	MatchConfig.clear()
	_start.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(HERO_SELECT_SCENE)
