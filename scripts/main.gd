extends Node2D
## Arena root: wires the on-screen joystick to the player and reports the
## joystick vector on the HUD so the input path is visible while playing.

@onready var player: Player = $Player
@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status

const HINT: String = "WASD / Arrows or drag the joystick to move"

func _ready() -> void:
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT

func _on_joystick_vector_changed(vector: Vector2) -> void:
	player.joystick_input = vector
	if vector == Vector2.ZERO:
		status_label.text = HINT
	else:
		status_label.text = "Joystick: (%.2f, %.2f)" % [vector.x, vector.y]
